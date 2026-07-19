"""pseudobulk()."""
import pytest


@pytest.fixture(scope="session")
def golden_pseudobulk(sc_orig):
    return sc_orig.qc(subset=True, allow_float=True, verbose=False)\
                  .pseudobulk("donor", "cell_type", num_threads=1, verbose=False)


@pytest.mark.parametrize("csc", [False, True], ids=["csr", "csc"])
@pytest.mark.parametrize("qc_column", [False, True], ids=["subset", "qc_col"])
@pytest.mark.parametrize("num_threads", [1, 2])
def test_pseudobulk(sc_orig, golden_pseudobulk, csc, qc_column, num_threads):
    sc = sc_orig.qc(remove_doublets=False, allow_float=True, verbose=False,
                    subset=not qc_column)
    if csc:
        sc = sc.tocsc()
    pb = sc.pseudobulk("donor", "cell_type", num_threads=num_threads, verbose=False)
    assert pb == golden_pseudobulk
