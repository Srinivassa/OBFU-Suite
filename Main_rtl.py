"""RTL launcher for the unmodified Main.py attack script.

RTL validation/test splits can contain exactly one labelled node per class.
numpy.loadtxt returns a zero-dimensional scalar for a one-line file, while
Main.py expects an array and calls len(...).  This launcher normalizes scalar
loadtxt results, then executes the original Main.py without modifying it.
"""

from pathlib import Path
import runpy

import numpy as np


_original_loadtxt = np.loadtxt


def _rtl_loadtxt(*args, **kwargs):
    """Keep one-value label files as a one-dimensional NumPy array."""
    return np.atleast_1d(_original_loadtxt(*args, **kwargs))


np.loadtxt = _rtl_loadtxt
runpy.run_path(str(Path(__file__).with_name("Main.py")), run_name="__main__")
