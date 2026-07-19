"""find_markers()."""
import pytest


@pytest.fixture(scope="session")
def num_cell_types(sc_orig):
    return sc_orig.obs["cell_type"].n_unique()


@pytest.fixture(scope="session")
def golden_markers(sc_orig):
    return {
        all_genes: sc_orig.qc(subset=True, allow_float=True, verbose=False)
                          .find_markers("cell_type", all_genes=all_genes,
                                        num_threads=1)
        for all_genes in (False, True)
    }


@pytest.mark.parametrize("all_genes", [False, True])
@pytest.mark.parametrize("csc", [False, True], ids=["csr", "csc"])
@pytest.mark.parametrize("qc_column", [False, True], ids=["subset", "qc_col"])
def test_find_markers(sc_orig, golden_markers, num_cell_types, all_genes, csc,
                      qc_column):
    golden = golden_markers[all_genes]
    for num_threads in (1, 2, num_cell_types + 1):
        sc = sc_orig.qc(allow_float=True, verbose=False, subset=not qc_column)
        if csc:
            sc = sc.tocsc()
        markers = sc.find_markers("cell_type", all_genes=all_genes,
                                  num_threads=num_threads)
        assert markers.equals(golden)
