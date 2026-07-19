"""Pseudobulk.qc(), library_size(), de() (needs R + limma)."""
import pytest


# Parse design: each sample is one donor under one treatment (PBS vs cytokine),
# so pseudobulk by sample and contrast stimulation vs control.
@pytest.mark.parametrize("group", [None, "treatment"],
                         ids=["ungrouped", "grouped"])
def test_pseudobulk_qc_library_size_de(sc_orig, require_r, group):
    # de() is single-threaded (no num_threads).
    res = {}
    for num_threads in (1, 2):
        pb = sc_orig.qc(verbose=False, allow_float=True)
        pb = pb.pseudobulk("sample", "cell_type", verbose=False,
                           num_threads=num_threads)
        pb = pb.qc("treatment", verbose=False)\
               .library_size(num_threads=num_threads)
        res[num_threads] = pb.de("~treatment", group=group, verbose=False)
    assert res[1] == res[2]
