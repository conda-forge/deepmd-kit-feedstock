set -e
SETUPTOOLS_SCM_PRETEND_VERSION=$PKG_VERSION pip install . --no-deps -vv

if [[ "$target_platform" == linux* ]]; then
# no libtensorflow_cc on osx

mkdir $SRC_DIR/source/build
cd $SRC_DIR/source/build
if [[ ${cuda_compiler_version} != "None" ]]; then
    DEEPMD_USE_CUDA_TOOLKIT=TRUE
else
    DEEPMD_USE_CUDA_TOOLKIT=FALSE
fi
cmake -D TENSORFLOW_ROOT=${PREFIX} \
	  -D CMAKE_INSTALL_PREFIX=${PREFIX} \
      -D USE_CUDA_TOOLKIT=${DEEPMD_USE_CUDA_TOOLKIT} \
	  -D LAMMPS_SOURCE_ROOT=$SRC_DIR/lammps \
	  $SRC_DIR/source
make #-j${CPU_COUNT}
make install
fi
