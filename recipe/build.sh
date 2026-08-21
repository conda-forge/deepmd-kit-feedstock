set -evx

# for libtorch
if [[ ${cuda_compiler_version} == 11.2 ]]; then
    export TORCH_CUDA_ARCH_LIST="3.5;5.0;6.0;6.1;7.0;7.5;8.0;8.6+PTX"
elif [[ ${cuda_compiler_version} == 11.8 ]]; then
    export TORCH_CUDA_ARCH_LIST="3.5;5.0;6.0;6.1;7.0;7.5;8.0;8.6;8.9+PTX"
elif [[ ${cuda_compiler_version} == 12.* ]]; then
    export TORCH_CUDA_ARCH_LIST="5.0;6.0;6.1;7.0;7.5;8.0;8.6;8.9;9.0;10.0;12.0+PTX"
elif [[ ${cuda_compiler_version} != "None" ]]; then
    echo "unsupported cuda version."
    exit 1
fi

if [[ ${cuda_compiler_version} != "None" ]]; then
    DEEPMD_USE_CUDA_TOOLKIT=TRUE
    DP_VARIANT=cuda

    # deepmd/kk passes Kokkos device views owned by LAMMPS across the plugin
    # boundary. Build against LAMMPS' vendored Kokkos release and the same
    # logical architecture setting as lammps-feedstock to keep that ABI
    # compatible. Native cubins avoid plugin-side driver JIT on known GPUs.
    # Reuse the backend's maintained architecture list for native Kokkos
    # cubins, retaining PTX only for the newest virtual architecture.
    DEEPMD_KOKKOS_CUDA_ARCHITECTURES=${TORCH_CUDA_ARCH_LIST//./}
    DEEPMD_KOKKOS_CUDA_ARCHITECTURES=${DEEPMD_KOKKOS_CUDA_ARCHITECTURES//+PTX/}
    KOKKOS_INSTALL_PREFIX=${SRC_DIR}/kokkos-install
    cmake -S ${SRC_DIR}/lammps/lib/kokkos \
          -B ${SRC_DIR}/kokkos-build \
          -G Ninja \
          ${CMAKE_ARGS} \
          -D CMAKE_BUILD_TYPE=Release \
          -D CMAKE_INSTALL_PREFIX=${KOKKOS_INSTALL_PREFIX} \
          -D CMAKE_INSTALL_LIBDIR=lib \
          -D CMAKE_POSITION_INDEPENDENT_CODE=ON \
          -D BUILD_SHARED_LIBS=OFF \
          -D Kokkos_ENABLE_CUDA=ON \
          -D Kokkos_ENABLE_CUDA_CONSTEXPR=ON \
          -D Kokkos_ENABLE_SERIAL=ON \
          -D Kokkos_ENABLE_OPENMP=OFF \
          -D Kokkos_ENABLE_TESTS=OFF \
          -D Kokkos_ENABLE_EXAMPLES=OFF \
          -D "Kokkos_CUDA_FATBIN_ARCHITECTURES=${DEEPMD_KOKKOS_CUDA_ARCHITECTURES}" \
          -D Kokkos_ARCH_MAXWELL50=ON
    cmake --build ${SRC_DIR}/kokkos-build --parallel ${CPU_COUNT} --verbose
    cmake --install ${SRC_DIR}/kokkos-build
    DEEPMD_KOKKOS_ARGS="-DDEEPMD_LAMMPS_KOKKOS=ON -DKokkos_DIR=${KOKKOS_INSTALL_PREFIX}/lib/cmake/Kokkos"
else
    DEEPMD_USE_CUDA_TOOLKIT=FALSE
    DP_VARIANT=cpu
    DEEPMD_KOKKOS_ARGS="-DDEEPMD_LAMMPS_KOKKOS=OFF"
fi
# TensorFlow 2.21 no longer exports TF_Version from the framework library used
# by Python extensions. The conda variant is authoritative and also works when
# cross-compiling, where the target Python cannot be executed. DeepMD's version
# parser requires a patch component before defining TF_*_VERSION for C++ code.
export CMAKE_ARGS="${CMAKE_ARGS} -D TENSORFLOW_VERSION=${tensorflow}.0"
if [[ "${target_platform}" == "osx-arm64" ]]; then
    export CMAKE_OSX_ARCHITECTURES="arm64"
fi
if [[ "${target_platform}" == "osx-arm64" || "${target_platform}" == "linux-aarch64" ]]; then
    export CMAKE_ARGS="${CMAKE_ARGS} -D CPP_CXX_ABI_RUN_RESULT_VAR=0 -D CPP_CXX_ABI_RUN_RESULT_VAR__TRYRUN_OUTPUT=0 -D PY_CXX_ABI_RESULT_VAR=0 -D PY_CXX_ABI_RESULT_VAR__TRYRUN_OUTPUT=0 -D PY_CXX_ABI_RUN_RESULT_VAR=0 -D PY_CXX_ABI_RUN_RESULT_VAR__TRYRUN_OUTPUT=0 -D TENSORFLOW_VERSION_RUN_RESULT_VAR=0 -D TENSORFLOW_VERSION_RUN_RESULT_VAR__TRYRUN_OUTPUT=2.18 -D TENSORFLOW_VERSION_RUN_RESULT_VAR__TRYRUN_OUTPUT_STDOUT=2.18 -D TENSORFLOW_VERSION_RUN_RESULT_VAR__TRYRUN_OUTPUT_STDERR=''"
    export TENSORFLOW_ROOT=${SP_DIR}/tensorflow
    export CMAKE_ARGS="${CMAKE_ARGS} -D TENSORFLOW_ROOT=${TENSORFLOW_ROOT}"
fi
if [[ "$CONDA_BUILD_CROSS_COMPILATION" == "1" && "${mpi}" == "openmpi" ]]; then
  export OPAL_PREFIX="$PREFIX"
fi
# TF and PT find protobuf conflict
perl -ni -e 'print unless /find_package\(Protobuf/' ${SP_DIR}/torch/share/cmake/Caffe2/public/protobuf.cmake
# -labsl_log_flags is the workaround for https://github.com/conda-forge/abseil-cpp-feedstock/issues/79.
# TensorFlow 2.21 headers also instantiate helpers provided by absl_strings.
export LDFLAGS="-labsl_log_flags -labsl_status -labsl_log_internal_message -labsl_log_internal_check_op -labsl_hash -labsl_raw_hash_set -labsl_strings ${LDFLAGS}"
DP_VARIANT=${DP_VARIANT} \
    DP_ENABLE_PYTORCH=1 \
	SETUPTOOLS_SCM_PRETEND_VERSION=$PKG_VERSION python -m pip install . -vv


mkdir $SRC_DIR/source/build
cd $SRC_DIR/source/build


cmake -D USE_TF_PYTHON_LIBS=TRUE \
      -D ENABLE_TENSORFLOW=TRUE \
      -D ENABLE_PYTORCH=TRUE \
	  -D CMAKE_INSTALL_PREFIX=${PREFIX} \
      -D USE_CUDA_TOOLKIT=${DEEPMD_USE_CUDA_TOOLKIT} \
      -D CMAKE_PREFIX_PATH=${SP_DIR}/torch/ \
	  ${CMAKE_ARGS} \
	  $SRC_DIR/source
make -j${CPU_COUNT} VERBOSE=1
make install

# Configure the plugin separately against the installed C API. A CUDA-enabled
# Kokkos package installs a global nvcc compiler launcher; isolating it here
# prevents the TensorFlow and PyTorch interface libraries above from being
# unnecessarily rebuilt by nvcc.
mkdir $SRC_DIR/source/plugin-build
cd $SRC_DIR/source/plugin-build
cmake -D BUILD_CPP_IF=TRUE \
      -D BUILD_PY_IF=FALSE \
      -D ENABLE_TENSORFLOW=FALSE \
      -D ENABLE_PYTORCH=FALSE \
      -D ALLOW_NO_BACKEND=TRUE \
	  -D CMAKE_INSTALL_PREFIX=${PREFIX} \
      -D DEEPMD_C_ROOT=${PREFIX} \
      -D USE_CUDA_TOOLKIT=${DEEPMD_USE_CUDA_TOOLKIT} \
	  ${DEEPMD_KOKKOS_ARGS} \
	  -D LAMMPS_SOURCE_ROOT=$SRC_DIR/lammps \
	  ${CMAKE_ARGS} \
	  $SRC_DIR/source
make -j${CPU_COUNT} VERBOSE=1
# This imported-C-API configuration also generates CMake package files for the
# already-installed DeePMD libraries. Stage its installation and copy only the
# LAMMPS module so the primary build's development exports remain intact.
PLUGIN_INSTALL_STAGE=${SRC_DIR}/plugin-install
DESTDIR="${PLUGIN_INSTALL_STAGE}" make install
cp -a "${PLUGIN_INSTALL_STAGE}${PREFIX}/lib"/libdeepmd_lmp.* "${PREFIX}/lib/"
mkdir -p "${PREFIX}/lib/deepmd_lmp"
cp -a "${PLUGIN_INSTALL_STAGE}${PREFIX}/lib/deepmd_lmp/." \
      "${PREFIX}/lib/deepmd_lmp/"

# Copy the [de]activate scripts to $PREFIX/etc/conda/[de]activate.d.
# This will allow them to be run on environment activation.
for CHANGE in "activate" "deactivate"
do
    mkdir -p "${PREFIX}/etc/conda/${CHANGE}.d"
    cp "${RECIPE_DIR}/${CHANGE}.sh" "${PREFIX}/etc/conda/${CHANGE}.d/${PKG_NAME}_${CHANGE}.sh"
done
