set SETUPTOOLS_SCM_PRETEND_VERSION=%PKG_VERSION%
pip install --install-option="-- -G %CMAKE_GENERATOR%" . --no-deps -vv
