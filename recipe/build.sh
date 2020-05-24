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
make lammps
cp -r USER-DEEPMD ../../lammps/src
mkdir -p ../../lammps/build
cd ../../lammps/build
cmake -D PKG_USER-DEEPMD=ON -D PKG_KSPACE=ON -D FFT=FFTW3 -D CMAKE_INSTALL_PREFIX=${PREFIX} -D CMAKE_CXX_FLAGS="-DHIGH_PREC -I${PREFIX}/include -I${PREFIX}/include/deepmd -L${PREFIX}/lib -Wl,--no-as-needed -ldeepmd_op -ldeepmd -ltensorflow_cc -ltensorflow_framework -lrt -Wl,-rpath=${PREFIX}/lib" ../cmake
make -j${NUM_CPUS}
make install

fi
