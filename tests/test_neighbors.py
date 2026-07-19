"""neighbors() and shared_neighbors()."""
import pytest


# neighbors()

@pytest.fixture(scope="session")
def golden_neighbors(sc_orig):
    return {
        kmeans: sc_orig.qc(subset=True, allow_float=True, verbose=False)
                       .hvg().normalize().pca()
                       .neighbors(num_threads=1, kmeans_barbar=kmeans)
        for kmeans in (False, True)
    }


@pytest.mark.parametrize("kmeans_barbar", [False, True],
                         ids=["random_init", "kmeans_barbar_init"])
@pytest.mark.parametrize("qc_column", [False, True], ids=["subset", "qc_col"])
@pytest.mark.parametrize("num_threads", [1, 2])
def test_neighbors(sc_orig, golden_neighbors, kmeans_barbar, qc_column,
                   num_threads):
    sc = sc_orig.qc(allow_float=True, verbose=False, subset=not qc_column)\
                .hvg().normalize().pca()\
                .neighbors(num_threads=num_threads, kmeans_barbar=kmeans_barbar)
    if qc_column:
        sc = sc.filter_obs("passed_QC").drop_obs("passed_QC")
    assert sc == golden_neighbors[kmeans_barbar]


# shared_neighbors()

@pytest.fixture(scope="session")
def golden_shared_neighbors(sc_orig):
    return sc_orig.qc(subset=True, allow_float=True, verbose=False)\
                  .hvg().normalize().pca().neighbors()\
                  .shared_neighbors(num_threads=1)


@pytest.mark.parametrize("qc_column", [False, True], ids=["subset", "qc_col"])
@pytest.mark.parametrize("num_threads", [1, 2])
def test_shared_neighbors(sc_orig, golden_shared_neighbors, qc_column,
                          num_threads):
    sc = sc_orig.qc(allow_float=True, verbose=False, subset=not qc_column)\
                .hvg().normalize().pca().neighbors()\
                .shared_neighbors(num_threads=num_threads)
    if qc_column:
        sc = sc.filter_obs("passed_QC").drop_obs("passed_QC")
    assert sc == golden_shared_neighbors
