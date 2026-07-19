from __future__ import annotations
from typing import Iterable
from .single_cell import SingleCell
from .pseudobulk import Pseudobulk
from .utils import check_type, to_tuple


def concat_obs(datasets: SingleCell | Iterable[SingleCell] |
                         Pseudobulk | Iterable[Pseudobulk],
               *more_datasets: SingleCell | Pseudobulk,
               dataset_column: str | None = None,
               dataset_labels: Iterable[str] | None = None,
               flexible: bool = False,
               num_threads: int | np.integer | None = None) -> \
        SingleCell | Pseudobulk:
    """
    Concatenate multiple SingleCell datasets cell-wise, or multiple Pseudobulk
    datasets sample-wise.

    Delegates to `SingleCell.concat_obs()` or `Pseudobulk.concat_obs()`,
    depending on whether the datasets are SingleCell or Pseudobulk.

    Args:
        datasets: one or more SingleCell or Pseudobulk datasets to concatenate
        *more_datasets: additional SingleCell or Pseudobulk datasets to
                        concatenate with this one, specified as positional
                        arguments
        dataset_column: the name of an Enum column to be added to the
                        concatenated dataset's `obs` labeling which dataset
                        each cell came from. The labels themselves are
                        determined by the `dataset_labels` argument.
        dataset_labels: a sequence of labels for each dataset, used to populate
                        `dataset_column`. There must be one label per dataset
                        being concatenated. If `dataset_labels` is not
                        specified, the labels default to `{dataset_column}_0`,
                        `{dataset_column}_1`, ..., `{dataset_column}_{N - 1}`.
                        Can only be specified when `dataset_column` is not
                        `None`.
        flexible: whether to subset to genes, columns of `obs` and `var`, and
                  (for SingleCell datasets) keys of `obsm`, `varm` and `uns`
                  common to all datasets before concatenating, rather than
                  raising an error on any mismatches
        num_threads: the number of threads to use when concatenating. Does not
                     affect the concatenated SingleCell or Pseudobulk dataset's
                     `num_threads`; this will always be the same as the first
                     dataset's `num_threads`.

    Returns:
        The concatenated SingleCell or Pseudobulk dataset.
    """
    if isinstance(datasets, (SingleCell, Pseudobulk)):
        datasets = (datasets,) + more_datasets
    else:
        datasets = tuple(datasets) + more_datasets
        check_type(datasets[0], 'the first dataset', (SingleCell, Pseudobulk),
                   'a SingleCell or Pseudobulk dataset')
    if isinstance(datasets[0], SingleCell):
        return datasets[0].concat_obs(
            datasets[1:], flexible=flexible, dataset_column=dataset_column,
            dataset_labels=dataset_labels, num_threads=num_threads)
    else:
        return datasets[0].concat_obs(
            datasets[1:], flexible=flexible, dataset_column=dataset_column,
            dataset_labels=dataset_labels)


def concat_var(datasets: SingleCell | Iterable[SingleCell] |
                         Pseudobulk | Iterable[Pseudobulk],
               *more_datasets: SingleCell | Pseudobulk,
               dataset_column: str | None = None,
               dataset_labels: Iterable[str] | None = None,
               flexible: bool = False,
               num_threads: int | np.integer | None = None) -> \
        SingleCell | Pseudobulk:
    """
    Concatenate multiple SingleCell datasets or multiple Pseudobulk datasets,
    gene-wise. This is much less common than the cell- or sample-wise
    concatenation provided by `concat_obs()`.

    Delegates to `SingleCell.concat_var()` or `Pseudobulk.concat_var()`,
    depending on whether the datasets are SingleCell or Pseudobulk.

    Args:
        datasets: one or more SingleCell or Pseudobulk datasets to concatenate
        *more_datasets: additional Pseudobulk datasets to concatenate with this
                        one, specified as positional arguments
        dataset_column: the name of an Enum column to be added to the
                        concatenated dataset's `var` labeling which dataset
                        each cell came from. The labels themselves are
                        determined by the `dataset_labels` argument.
        dataset_labels: a sequence of labels for each dataset, used to populate
                        `dataset_column`. There must be one label per dataset
                        being concatenated. If `dataset_labels` is not
                        specified, the labels default to `{dataset_column}_0`,
                        `{dataset_column}_1`, ..., `{dataset_column}_{N - 1}`.
                        Can only be specified when `dataset_column` is not
                        `None`.
        flexible: whether to subset to cells/samples, columns of `obs` and
                  `var`, and (for SingleCell datasets) keys of `obsm`, `varm`
                  and `uns` common to all datasets before concatenating, rather
                  than raising an error on any mismatches
        num_threads: the number of threads to use when concatenating. Does not
                     affect the concatenated SingleCell/Pseudobulk dataset's
                     `num_threads`; this will always be the same as the first
                     dataset's `num_threads`.

    Returns:
        The concatenated SingleCell or Pseudobulk dataset.
    """
    if isinstance(datasets, (SingleCell, Pseudobulk)):
        datasets = (datasets,) + more_datasets
    else:
        datasets = tuple(datasets) + more_datasets
        check_type(datasets[0], 'the first dataset', (SingleCell, Pseudobulk),
                   'a SingleCell or Pseudobulk dataset')
    if isinstance(datasets[0], SingleCell):
        return datasets[0].concat_var(
            datasets[1:], flexible=flexible, dataset_column=dataset_column,
            dataset_labels=dataset_labels, num_threads=num_threads)
    else:
        return datasets[0].concat_var(
            datasets[1:], flexible=flexible, dataset_column=dataset_column,
            dataset_labels=dataset_labels)