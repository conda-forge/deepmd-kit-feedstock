set -e
SETUPTOOLS_SCM_PRETEND_VERSION=$PKG_VERSION pip install . --no-deps -vv

if [[ "$target_platform" == linux* ]]; then
# no libtensorflow_cc on osx

mkdir source/build
cd source/build
cmake -D TENSORFLOW_ROOT=${PREFIX} \
	  -D CMAKE_INSTALL_PREFIX=${PREFIX} \
	  ..
make -j${CPU_COUNT}
make install

fi
