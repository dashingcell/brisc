"""normalize()."""
import numpy as np
import pytest


_METHODS = ["logCP10k", "log1pPF", "PFlog1pPF"]


@pytest.fixture(scope="session")
def golden_normalize(sc_orig):
    return {
        method: sc_orig.qc(subset=True, allow_float=True, verbose=False)
                       .normalize(method=method, num_threads=1)
        for method in _METHODS
    }


@pytest.mark.parametrize("method", _METHODS)
@pytest.mark.parametrize("csc", [False, True], ids=["csr", "csc"])
@pytest.mark.parametrize("qc_column", [False, True], ids=["subset", "qc_col"])
@pytest.mark.parametrize("num_threads", [1, 2])
def test_normalize(sc_orig, golden_normalize, method, csc, qc_column,
                   num_threads):
    golden = golden_normalize[method]
    sc = sc_orig.qc(allow_float=True, verbose=False, subset=not qc_column)
    if csc:
        sc = sc.tocsc()
    sc = sc.normalize(method=method, num_threads=num_threads)
    if qc_column:
        sc = sc.filter_obs("passed_QC")
    if csc:
        sc = sc.tocsr()
    assert np.abs(sc.X.data - golden.X.data).max() == 0
