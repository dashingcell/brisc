"""cluster()."""
import pytest


@pytest.fixture(scope="session")
def golden_cluster(sc_orig):
    return sc_orig.qc(subset=True, allow_float=True, verbose=False)\
                  .hvg().normalize().pca()\
                  .neighbors().shared_neighbors().cluster()


@pytest.mark.parametrize("qc_column", [False, True], ids=["subset", "qc_col"])
@pytest.mark.parametrize("num_threads", [1, 2])
def test_cluster(sc_orig, golden_cluster, qc_column, num_threads):
    sc = sc_orig.qc(allow_float=True, verbose=False, subset=not qc_column)\
                .hvg().normalize().pca().neighbors().shared_neighbors()
    if num_threads == 1:
        sc = sc.cluster()
    else:  # multi-resolution path; alias cluster_0 -> cluster
        sc = sc.cluster(resolution=[1, 0.9])\
                .rename_obs({"cluster_0": "cluster"})
    if qc_column:
        sc = sc.filter_obs("passed_QC")
    assert sc.obs["cluster"].equals(golden_cluster.obs["cluster"])
