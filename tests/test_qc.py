"""qc_metrics(), qc(), find_doublets(), doublets in/out of qc()."""
import polars as pl
import pytest


# qc_metrics()

@pytest.fixture(scope="session")
def golden_qc_metrics(sc_orig):
    return sc_orig.qc_metrics(num_threads=1, allow_float=True)


@pytest.mark.parametrize("csc", [False, True], ids=["csr", "csc"])
@pytest.mark.parametrize("num_threads", [1, 2])
def test_qc_metrics(sc_orig, golden_qc_metrics, csc, num_threads):
    sc = sc_orig.tocsc() if csc else sc_orig
    sc = sc.qc_metrics(num_threads=num_threads, allow_float=True)
    assert sc.obs.equals(golden_qc_metrics.obs)


# qc()

_QC_CASES = [(False, None), (True, None), (True, "donor")]


@pytest.fixture(scope="session")
def golden_qc(sc_orig):
    return {
        (rm, bc): sc_orig.qc(
            subset=True, remove_doublets=rm, batch_column=bc, num_threads=1,
            allow_float=True, verbose=False)
        for rm, bc in _QC_CASES
    }


@pytest.mark.parametrize("remove_doublets,batch_column", _QC_CASES)
@pytest.mark.parametrize("csc", [False, True], ids=["csr", "csc"])
@pytest.mark.parametrize("qc_column", [False, True], ids=["subset", "qc_col"])
@pytest.mark.parametrize("num_threads", [1, 2])
def test_qc(sc_orig, golden_qc, remove_doublets, batch_column, csc, qc_column,
            num_threads):
    golden = golden_qc[(remove_doublets, batch_column)]
    sc = sc_orig.tocsc() if csc else sc_orig
    sc = sc.qc(remove_doublets=remove_doublets, batch_column=batch_column,
               num_threads=num_threads, allow_float=True, verbose=False,
               subset=not qc_column)
    if qc_column:
        sc = sc.filter_obs("passed_QC")
    assert sc.obs_names.equals(golden.obs_names)


# find_doublets()

@pytest.fixture(scope="session")
def golden_find_doublets(sc_orig):
    out = {}
    for bc in (None, "donor"):
        for frac in (None, 0.2):
            out[(bc, frac)] = (
                sc_orig
                .qc(subset=True, remove_doublets=False, num_threads=1,
                    allow_float=True, verbose=False)
                .find_doublets(batch_column=bc, doublet_fraction=frac))
    return out


@pytest.mark.parametrize("batch_column", [None, "donor"])
@pytest.mark.parametrize("doublet_fraction", [None, 0.2])
@pytest.mark.parametrize("csc", [False, True], ids=["csr", "csc"])
@pytest.mark.parametrize("qc_column", [False, True], ids=["subset", "qc_col"])
@pytest.mark.parametrize("num_threads", [1, 2])
@pytest.mark.parametrize("return_scores", [True, False])
def test_find_doublets(sc_orig, golden_find_doublets, batch_column,
                       doublet_fraction, csc, qc_column, num_threads,
                       return_scores):
    golden = golden_find_doublets[(batch_column, doublet_fraction)]
    sc = sc_orig.qc(remove_doublets=False, allow_float=True, verbose=False,
                    subset=not qc_column)
    if csc:
        sc = sc.tocsc()
    sc = sc.find_doublets(
        batch_column=batch_column, doublet_fraction=doublet_fraction,
        doublet_score_column="doublet_score" if return_scores else None,
        num_threads=num_threads)
    if qc_column:
        sc = sc.filter_obs("passed_QC")
    assert sc.obs["doublet"].equals(golden.obs["doublet"])
    if return_scores:
        assert sc.obs["doublet_score"].equals(golden.obs["doublet_score"])


# doublet finding inside vs. outside qc()

@pytest.mark.parametrize("qc_column", [False, True], ids=["subset", "qc_col"])
@pytest.mark.parametrize("num_threads", [1, 2])
def test_doublets_inside_vs_outside_qc(sc_orig, qc_column, num_threads):
    a = (sc_orig
         .qc(verbose=False, allow_float=True, subset=not qc_column,
             num_threads=num_threads)
         .find_doublets(batch_column="donor", num_threads=num_threads)
         .filter_obs(~pl.col.doublet))
    b = sc_orig.qc(verbose=False, allow_float=True, remove_doublets=True,
                   batch_column="donor", subset=not qc_column,
                   num_threads=num_threads)
    if qc_column:
        a = a.filter_obs("passed_QC")
        b = b.filter_obs("passed_QC")
    assert a.shape == b.shape
