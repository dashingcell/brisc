"""Shared fixtures for the brisc test suite."""
import shutil
import pytest

_FIXTURE = "Parse_10K_PBMC_cytokines.h5ad"
_HF_REPO = "dashingcell/Parse_10K_PBMC_cytokines"


@pytest.fixture(scope="session")
def data_path():
    # Pull the ~0.15 GB fixture from the public HF dataset (cached under
    # ~/.cache/huggingface).
    from huggingface_hub import hf_hub_download
    return hf_hub_download(_HF_REPO, _FIXTURE, repo_type="dataset")


@pytest.fixture(scope="session")
def sc_orig(data_path):
    from brisc import SingleCell
    return SingleCell(data_path)


@pytest.fixture(scope="session")
def require_r():
    # R is installed in CI, so a broken ryp/limma should fail loudly, not skip.
    if shutil.which("R") is None and shutil.which("Rscript") is None:
        pytest.skip("R not installed")
    import ryp
    ryp.r("suppressMessages(library(limma))")
    return True
