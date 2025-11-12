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
    if [ -f ${SP_DIR}/tensorflow ]; then
        export TENSORFLOW_ROOT=${SP_DIR}/tensorflow
    else
        export TENSORFLOW_ROOT=${PREFIX}
    fi
    export CMAKE_ARGS="${CMAKE_ARGS} -D TENSORFLOW_ROOT=${TENSORFLOW_ROOT}"
fi
if [[ "$CONDA_BUILD_CROSS_COMPILATION" == "1" && "${mpi}" == "openmpi" ]]; then
  export OPAL_PREFIX="$PREFIX"
fi
# TF and PT find protobuf conflict
if [ "$(uname)" == "Darwin" ]; then
    # sed -i '' -e '4d' ${SP_DIR}/torch/share/cmake/Caffe2/public/protobuf.cmake
	echo pass
else
    sed -i "4d" ${PREFIX}/share/cmake/Caffe2/public/protobuf.cmake
fi
# -labsl_log_flags is the workaround for https://github.com/conda-forge/abseil-cpp-feedstock/issues/79
export LDFLAGS="-labsl_log_flags -labsl_status -labsl_log_internal_message -labsl_hash ${LDFLAGS}"