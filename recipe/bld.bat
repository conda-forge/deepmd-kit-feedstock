set SETUPTOOLS_SCM_PRETEND_VERSION=%PKG_VERSION%
pip install --install-option="-G'NMake Makefiles'" . --no-deps -vv
