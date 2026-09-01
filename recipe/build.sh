set -evx

# PyTorch extensions use toolkit-specific architecture spellings.  Kokkos is
# configured separately below because it uses its own architecture names.
if [[ ${cuda_compiler_version} == 11.2 ]]; then
    export TORCH_CUDA_ARCH_LIST="3.5;5.0;6.0;6.1;7.0;7.5;8.0;8.6+PTX"
    DEEPMD_KOKKOS_ARCH=MAXWELL50
elif [[ ${cuda_compiler_version} == 11.8 ]]; then
    export TORCH_CUDA_ARCH_LIST="3.5;5.0;6.0;6.1;7.0;7.5;8.0;8.6;8.9+PTX"
    DEEPMD_KOKKOS_ARCH=MAXWELL50
elif [[ ${cuda_compiler_version} == 12.* ]]; then
    export TORCH_CUDA_ARCH_LIST="5.0;6.0;6.1;7.0;7.5;8.0;8.6;8.9;9.0;10.0;12.0+PTX"
    DEEPMD_KOKKOS_ARCH=MAXWELL50
elif [[ ${cuda_compiler_version} == 13.* ]]; then
    # CUDA 13 dropped pre-Turing targets and renamed sm_101 to sm_110.
    export TORCH_CUDA_ARCH_LIST="7.5;8.0;8.6;8.9;9.0;10.0;11.0;12.0+PTX"
    DEEPMD_KOKKOS_ARCH=TURING75
elif [[ ${cuda_compiler_version} != "None" ]]; then
    echo "unsupported cuda version."
    exit 1
fi

if [[ ${cuda_compiler_version} != "None" ]]; then
    DEEPMD_USE_CUDA_TOOLKIT=TRUE
    DP_VARIANT=cuda

    # Build Kokkos from the LAMMPS source tree so the plugin and LAMMPS share
    # one Kokkos ABI.  The nvcc activation script supplies the exact real and
    # virtual targets, including CUDA 13 suffixes such as 100f.
    if [[ -z ${CUDAARCHS:-} ]]; then
        echo "CUDAARCHS was not set by the CUDA compiler activation script."
        exit 1
    fi
    DEEPMD_KOKKOS_CUDA_ARCHITECTURES=${CUDAARCHS}
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
          -D "Kokkos_ARCH_${DEEPMD_KOKKOS_ARCH}=ON"
    cmake --build ${SRC_DIR}/kokkos-build --parallel ${CPU_COUNT} --verbose
    cmake --install ${SRC_DIR}/kokkos-build
    DEEPMD_KOKKOS_ARGS="-DDEEPMD_LAMMPS_KOKKOS=ON -DKokkos_DIR=${KOKKOS_INSTALL_PREFIX}/lib/cmake/Kokkos"
else
    DEEPMD_USE_CUDA_TOOLKIT=FALSE
    DP_VARIANT=cpu
    DEEPMD_KOKKOS_ARGS="-DDEEPMD_LAMMPS_KOKKOS=OFF"
fi
# TensorFlow 2.21 no longer exports TF_Version from the framework library used
# by Python extensions.  The conda variant is authoritative, including during
# cross compilation, and DeepMD's parser expects a patch component.
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

# The standalone libtorch CMake config expects its Protobuf imported target to
# exist already.  TensorFlow can find the headers without creating that target,
# so initialize Protobuf explicitly before Torch is discovered.
perl -0pi -e 's/  find_package\(Torch REQUIRED\)/  find_package(Protobuf REQUIRED)\n  find_package(Torch REQUIRED)/' \
    $SRC_DIR/source/CMakeLists.txt

mkdir $SRC_DIR/source/build
cd $SRC_DIR/source/build

# libtensorflow_cc keeps its vendored Eigen and XLA trees below
# tensorflow/third_party rather than at the roots expected by public headers.
export CXXFLAGS="${CXXFLAGS} -I${PREFIX}/include/tensorflow/third_party -I${PREFIX}/include/tensorflow/third_party/xla"

cmake ${CMAKE_ARGS} \
      -D USE_TF_PYTHON_LIBS=FALSE \
      -D USE_PT_PYTHON_LIBS=FALSE \
      -D ENABLE_TENSORFLOW=TRUE \
      -D ENABLE_PYTORCH=TRUE \
	  -D CMAKE_INSTALL_PREFIX=${PREFIX} \
      -D USE_CUDA_TOOLKIT=${DEEPMD_USE_CUDA_TOOLKIT} \
	  -D LAMMPS_SOURCE_ROOT=$SRC_DIR/lammps \
	  -D TENSORFLOW_ROOT=${PREFIX} \
	  -D CMAKE_PREFIX_PATH=${PREFIX} \
	  $SRC_DIR/source
make -j${CPU_COUNT} VERBOSE=1
make install

# Configure the plugin separately against the installed C API.  Kokkos' CUDA
# compiler launcher must not leak into the TensorFlow/PyTorch build above.
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
# Stage the plugin installation and copy only its module.  This preserves the
# primary build's CMake exports while honoring the plugin's generated files.
PLUGIN_INSTALL_STAGE=${SRC_DIR}/plugin-install
DESTDIR="${PLUGIN_INSTALL_STAGE}" make install
cp -a "${PLUGIN_INSTALL_STAGE}${PREFIX}/lib"/libdeepmd_lmp.* "${PREFIX}/lib/"
mkdir -p "${PREFIX}/lib/deepmd_lmp"
ln -sfn ../libdeepmd_lmp.so "${PREFIX}/lib/deepmd_lmp/dpplugin.so"

# Copy the [de]activate scripts to $PREFIX/etc/conda/[de]activate.d.
# This will allow them to be run on environment activation.
for CHANGE in "activate" "deactivate"
do
    mkdir -p "${PREFIX}/etc/conda/${CHANGE}.d"
    cp "${RECIPE_DIR}/${CHANGE}.sh" "${PREFIX}/etc/conda/${CHANGE}.d/${PKG_NAME}_${CHANGE}.sh"
done
