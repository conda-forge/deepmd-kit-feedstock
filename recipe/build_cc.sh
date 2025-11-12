set -evx

export TENSORFLOW_ROOT=${PREFIX}
source $RECIPE_DIR/build_common.sh

mkdir $SRC_DIR/source/build
cd $SRC_DIR/source/build


cmake -D USE_TF_PYTHON_LIBS=FALSE \
      -D USE_PT_PYTHON_LIBS=FALSE \
      -D ENABLE_TENSORFLOW=TRUE \
      -D ENABLE_PYTORCH=TRUE \
	  -D CMAKE_INSTALL_PREFIX=${PREFIX} \
      -D USE_CUDA_TOOLKIT=${DEEPMD_USE_CUDA_TOOLKIT} \
	  -D LAMMPS_SOURCE_ROOT=$SRC_DIR/lammps \
	  ${CMAKE_ARGS} \
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
