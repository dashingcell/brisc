"""pca()."""
import numpy as np
import pytest


@pytest.fixture(scope="session")
def golden_pca(sc_orig):
    return sc_orig.qc(subset=True, allow_float=True, verbose=False)\
                  .hvg().normalize().pca(num_threads=1, match_parallel=True)


@pytest.mark.parametrize("csc", [False, True], ids=["csr", "csc"])
@pytest.mark.parametrize("qc_column", [False, True], ids=["subset", "qc_col"])
@pytest.mark.parametrize("num_threads", [1, 2])
def test_pca(sc_orig, golden_pca, csc, qc_column, num_threads):
    sc = sc_orig.qc(allow_float=True, verbose=False, subset=not qc_column)\
                .hvg().normalize()
    if csc:
        sc = sc.tocsc()
    sc = sc.pca(num_threads=num_threads, match_parallel=num_threads == 1)
    if qc_column:
        sc = sc.filter_obs("passed_QC")
    if csc:
        sc = sc.tocsr()
    assert np.array_equal(sc.obsm["pca"], golden_pca.obsm["pca"])
