set -e
SETUPTOOLS_SCM_PRETEND_VERSION=$PKG_VERSION pip install . --no-deps -vv

if [[ "$target_platform" == linux* ]]; then
# no libtensorflow_cc on osx

# copy absl headers to prevent conflict
rsync -avzh --include '*/' --include '*.h' --include '*.inc' --exclude '*' $SRC_DIR/absl/absl/ $PREFIX/include/absl/

mkdir $SRC_DIR/source/build
cd $SRC_DIR/source/build
cmake -D TENSORFLOW_ROOT=${PREFIX} \
	  -D CMAKE_INSTALL_PREFIX=${PREFIX} \
	  $SRC_DIR/source
make #-j${CPU_COUNT}
make install
make lammps
cp -r $SRC_DIR/source/build/USER-DEEPMD $SRC_DIR/lammps/src
mkdir -p $SRC_DIR/lammps/build
cd $SRC_DIR/lammps/build
cmake -D PKG_USER-DEEPMD=ON -D FFT=FFTW3 -D CMAKE_INSTALL_PREFIX=${PREFIX} -D CMAKE_CXX_FLAGS="-DHIGH_PREC -I${PREFIX}/include -I${PREFIX}/include/deepmd -L${PREFIX}/lib -Wl,--no-as-needed -ldeepmd_op -ldeepmd -ltensorflow_cc -ltensorflow_framework -lrt -Wl,-rpath=${PREFIX}/lib" $SRC_DIR/lammps/cmake
make #-j${NUM_CPUS}
make install

fi
