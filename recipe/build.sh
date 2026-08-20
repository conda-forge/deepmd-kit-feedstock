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
else
    DEEPMD_USE_CUDA_TOOLKIT=FALSE
    DP_VARIANT=cpu
fi
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
# -labsl_log_flags is the workaround for https://github.com/conda-forge/abseil-cpp-feedstock/issues/79
export LDFLAGS="-labsl_log_flags -labsl_status -labsl_log_internal_message -labsl_hash -labsl_raw_hash_set ${LDFLAGS}"
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
make VERBOSE=1 #-j${CPU_COUNT}
make install

# Copy the [de]activate scripts to $PREFIX/etc/conda/[de]activate.d.
# This will allow them to be run on environment activation.
for CHANGE in "activate" "deactivate"
do
    mkdir -p "${PREFIX}/etc/conda/${CHANGE}.d"
    cp "${RECIPE_DIR}/${CHANGE}.sh" "${PREFIX}/etc/conda/${CHANGE}.d/${PKG_NAME}_${CHANGE}.sh"
done
