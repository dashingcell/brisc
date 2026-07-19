"""harmonize() and label_transfer_from()."""
import pytest


def _prep_pair(sc_orig, subset):
    # split into query (stimulated) and reference (control) arms
    parts = sc_orig.split_by_obs("treatment", QC_column=None)
    sc = parts["cytokine"].qc(allow_float=True, verbose=False, subset=subset)
    sc_ref = parts["PBS"].qc(allow_float=True, verbose=False, subset=subset)
    sc, sc_ref = sc.hvg(sc_ref, verbose=False)
    sc, sc_ref = sc.normalize(), sc_ref.normalize()
    sc, sc_ref = sc.pca(sc_ref)
    return sc, sc_ref


# harmonize()

@pytest.fixture(scope="session")
def golden_harmonize(sc_orig):
    sc, sc_ref = _prep_pair(sc_orig, subset=True)
    return sc.harmonize(sc_ref, verbose=False, num_threads=1)


@pytest.mark.parametrize("qc_column", [False, True], ids=["subset", "qc_col"])
@pytest.mark.parametrize("num_threads", [1, 2])
def test_harmonize(sc_orig, golden_harmonize, qc_column, num_threads):
    golden, golden_ref = golden_harmonize
    sc, sc_ref = _prep_pair(sc_orig, subset=not qc_column)
    sc, sc_ref = sc.harmonize(sc_ref, verbose=False, num_threads=num_threads)
    if qc_column:
        sc = sc.filter_obs("passed_QC").drop_obs("passed_QC")
        sc_ref = sc_ref.filter_obs("passed_QC").drop_obs("passed_QC")
    assert sc == golden
    assert sc_ref == golden_ref


# label_transfer_from()

@pytest.fixture(scope="session")
def golden_label_transfer(sc_orig):
    sc, sc_ref = _prep_pair(sc_orig, subset=True)
    sc, sc_ref = sc.harmonize(sc_ref, verbose=False)
    return sc.label_transfer_from(
        sc_ref, "cell_type", verbose=False, num_threads=1,
        cell_type_column="predicted_cell_type")


@pytest.mark.parametrize("qc_column", [False, True], ids=["subset", "qc_col"])
@pytest.mark.parametrize("num_threads", [1, 2])
def test_label_transfer(sc_orig, golden_label_transfer, qc_column, num_threads):
    sc, sc_ref = _prep_pair(sc_orig, subset=not qc_column)
    sc, sc_ref = sc.harmonize(sc_ref, verbose=False)
    sc = sc.label_transfer_from(
        sc_ref, "cell_type", verbose=False, num_threads=num_threads,
        cell_type_column="predicted_cell_type")
    if qc_column:
        sc = sc.filter_obs("passed_QC").drop_obs("passed_QC")
    assert sc == golden_label_transfer
