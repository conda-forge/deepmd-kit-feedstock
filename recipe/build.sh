set -e

if [[ ${cuda_compiler_version} != "None" ]]; then
    DEEPMD_USE_CUDA_TOOLKIT=TRUE
    DP_VARIANT=cuda
else
    DEEPMD_USE_CUDA_TOOLKIT=FALSE
    DP_VARIANT=cpu
fi
if [[ "${target_platform}" == "osx-arm64" ]]; then
    export CMAKE_OSX_ARCHITECTURES="arm64"
    export CMAKE_ARGS="${CMAKE_ARGS} -D CPP_CXX_ABI_RUN_RESULT_VAR=0 -D CPP_CXX_ABI_RUN_RESULT_VAR__TRYRUN_OUTPUT=0 -D PY_CXX_ABI_RESULT_VAR=0 -D PY_CXX_ABI_RESULT_VAR__TRYRUN_OUTPUT=0 -D PY_CXX_ABI_RUN_RESULT_VAR=0 -D PY_CXX_ABI_RUN_RESULT_VAR__TRYRUN_OUTPUT=0 -D TENSORFLOW_VERSION_RUN_RESULT_VAR=0 -D TENSORFLOW_VERSION_RUN_RESULT_VAR__TRYRUN_OUTPUT=2.12"
    export TENSORFLOW_ROOT=${SP_DIR}/tensorflow
    export CMAKE_ARGS="${CMAKE_ARGS} -D TENSORFLOW_ROOT=${TENSORFLOW_ROOT}"
fi
export LDFLAGS="-labsl_status -labsl_logging_internal ${LDFLAGS}"
DP_VARIANT=${DP_VARIANT} \
	SETUPTOOLS_SCM_PRETEND_VERSION=$PKG_VERSION python -m pip install . -vv


mkdir $SRC_DIR/source/build
cd $SRC_DIR/source/build


cmake -D USE_TF_PYTHON_LIBS=TRUE \
	  -D CMAKE_INSTALL_PREFIX=${PREFIX} \
      -D USE_CUDA_TOOLKIT=${DEEPMD_USE_CUDA_TOOLKIT} \
	  -D LAMMPS_SOURCE_ROOT=$SRC_DIR/lammps \
	  ${CMAKE_ARGS} \
	  $SRC_DIR/source
make #-j${CPU_COUNT}
make install

# Copy the [de]activate scripts to $PREFIX/etc/conda/[de]activate.d.
# This will allow them to be run on environment activation.
for CHANGE in "activate" "deactivate"
do
    mkdir -p "${PREFIX}/etc/conda/${CHANGE}.d"
    cp "${RECIPE_DIR}/${CHANGE}.sh" "${PREFIX}/etc/conda/${CHANGE}.d/${PKG_NAME}_${CHANGE}.sh"
done
