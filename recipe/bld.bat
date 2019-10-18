set SETUPTOOLS_SCM_PRETEND_VERSION=%PKG_VERSION%
pip install --install-option="-GNMake Makefiles" . --no-deps -vv
