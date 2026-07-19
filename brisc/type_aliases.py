from __future__ import annotations
import numpy as np
import polars as pl
from datetime import date, datetime, time, timedelta
from decimal import Decimal
from typing import Callable, Dict, Union


Color = Union[str, float, np.floating,
              tuple[Union[int, np.integer], Union[int, np.integer],
                    Union[int, np.integer]],
              tuple[Union[int, np.integer], Union[int, np.integer],
                    Union[int, np.integer], Union[int, np.integer]],
              tuple[Union[float, np.floating], Union[float, np.floating],
                    Union[float, np.floating]],
              tuple[Union[float, np.floating], Union[float, np.floating],
                    Union[float, np.floating], Union[float, np.floating]]]
Indexer = Union[int, np.integer, str, slice,
                np.ndarray[Union[np.dtype[np.integer], np.dtype[np.bool_]]],
                pl.Series, list[Union[int, np.integer, str, bool, np.bool_]]]
Scalar = Union[str, int, float, Decimal, date, time, datetime, timedelta, bool,
               bytes]
UnsDict = \
    Dict[str, Union[str, int, np.integer, float, np.floating, bool, np.bool_,
                    np.ndarray, 'UnsDict']]
UnsItem = str, int, np.integer, float, np.floating, bool, np.bool_, np.ndarray
SingleCellColumn = \
    Union[str, pl.Expr, pl.Series, np.ndarray,
          Callable[['SingleCell'], Union[pl.Series, np.ndarray]]]
PseudobulkColumn = \
    Union[str, pl.Expr, pl.Series, np.ndarray,
          Callable[['Pseudobulk', str], Union[pl.Series, np.ndarray]]]