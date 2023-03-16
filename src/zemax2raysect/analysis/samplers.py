"""Functions to sample points in different fashions."""
import numpy as np


def _check_args(radius: float, n: int) -> None:

    if radius <= 0:
        raise ValueError(f"radius cannot be less than or equal to zero, got {radius}")

    if not isinstance(n, int):
        raise TypeError(f"ray density 'n' has to be int, got {type(n)}")

    if n <= 0:
        raise ValueError(f"ray density 'n' cannot be less than or equal to zero, got {n}")


def sample_x_fan(radius: float, n: int) -> np.ndarray:
    """Sample X-fan.

    Samples points from -radius to +radius along X-axis.
    Resulting array contains 2 * n + 1 points along the first axis. samples[0] is always (0, 0).

    Parameters
    ----------
    radius : float
        Total sampling radius.
    n : int
        Point density.

    Returns
    -------
    samples : np.ndarray of shape (2 * n + 1, 2)
    """
    _check_args(radius, n)

    samples = np.zeros((2 * n + 1, 2))
    step = radius / n

    samples[1 : n + 1, 0] = np.linspace(-radius, -step, n, dtype=float)
    samples[n + 1 :, 0] = np.linspace(step, radius, n, dtype=float)

    return samples


def sample_y_fan(radius: float, n: int) -> np.ndarray:
    """Sample Y-fan.

    Samples points from -radius to +radius along Y-axis.
    Resulting array contains 2 * n + 1 points along the first axis. samples[0] is always (0, 0).

    Parameters
    ----------
    radius : float
        Total sampling radius.
    n : int
        Point density.

    Returns
    -------
    samples : np.ndarray of shape (2 * n + 1, 2)
    """
    _check_args(radius, n)

    samples = np.zeros((2 * n + 1, 2))
    # step = radius / n

    # samples[1 : n + 1, 1] = np.linspace(-radius, -step, n)
    # samples[n + 1 :, 1] = np.linspace(step, radius, n)

    samples[:, 1] = sample_x_fan(radius, n)[:, 0]

    return samples


def sample_xy_fan(radius: float, n: int) -> np.ndarray:
    """Sample XY-fan.

    Samples points from -radius to +radius along X-axis and Y-axis.
    Resulting array contains 4 * n + 1 points along the first axis. samples[0] is always (0, 0).

    Parameters
    ----------
    radius : float
        Total sampling radius.
    n : int
        Point density.

    Returns
    -------
    samples : np.ndarray of shape (4 * n + 1, 2)
    """
    _check_args(radius, n)

    samples = np.zeros((4 * n + 1, 2))
    # step = radius / n

    # samples[1 : n + 1, 0] = np.linspace(-radius, -step, n, dtype=float)
    # samples[n + 1 : 2 * n + 1, 0] = np.linspace(step, radius, n, dtype=float)
    # samples[2 * n + 1 : 3 * n + 1, 1] = np.linspace(-radius, -step, n, dtype=float)
    # samples[3 * n + 1 :, 1] = np.linspace(step, radius, n, dtype=float)

    samples[: 2 * n + 1] = sample_x_fan(radius, n)
    samples[2 * n + 1 :] = sample_y_fan(radius, n)[1:]

    return samples


def sample_hexapolar(radius: float, n: int) -> np.ndarray:
    """Sample points using hexapolar pattern.

    Hexapolar patterns consists of equally spaced rings from 0 to radius.
    Each ring consists of multiple of 6 points.
    Resulting array contains 3 * (n + 1) * n + 1 points along the first axis.
    samples[0] is always (0, 0).

    Parameters
    ----------
    radius : float
        Total sampling radius.
    n : int
        Point density.

    Returns
    -------
    samples : np.ndarray of shape (3 * (n + 1) * n + 1, 2)
    """
    _check_args(radius, n)

    m = 3 * (n + 1) * n + 1
    r = np.linspace(0, radius, n + 1)
    samples = np.zeros((m, 2), dtype=float)

    for i, _r in enumerate(r[1:], start=1):

        m = 3 * (i - 1) * i + 1
        theta = np.linspace(0, 2 * np.pi, 6 * i, endpoint=False)
        for j, _t in enumerate(theta):
            samples[m + j, :] = _r * np.cos(_t), _r * np.sin(_t)

    return np.array(samples, dtype=float)


def sample_square(radius: float, n: int) -> np.ndarray:
    """Sample points using square pattern.

    Resulting array contains (2 * n + 1)^2 points along the first axis.
    samples[0] is not (0, 0).

    Parameters
    ----------
    radius : float
        Total sampling radius.
    n : int
        Point density.

    Returns
    -------
    samples : np.ndarray of shape ((2 * n + 1)^2, 2)
    """
    _check_args(radius, n)

    m = 2 * n + 1
    samples = np.zeros((m**2, 2))
    x_samples = np.linspace(-radius, radius, m)

    for j, x in enumerate(x_samples):
        samples[j * m : (j + 1) * m, 0] = x_samples
        samples[j * m : (j + 1) * m, 1] = np.repeat(x, m)

    return samples


def sample_dither(radius: float, n: int) -> np.ndarray:
    """Sample points uniformly in a circle.

    Resulting array contains n^2 points along the first axis.
    samples[0] is not (0, 0).

    Parameters
    ----------
    radius : float
        Total sampling radius.
    n : int
        Point density.

    Returns
    -------
    samples : np.ndarray of shape (n^2, 2)
    """
    _check_args(radius, n)

    length = np.sqrt(np.random.uniform(0, radius**2, n**2))
    angle = np.pi * np.random.uniform(0, 2, n**2)
    x_samples = length * np.cos(angle)
    y_samples = length * np.sin(angle)

    return np.column_stack((x_samples, y_samples))


def sample_ring(radius: float, n: int) -> np.ndarray:
    """Sample points in a ring.

    Samples n points evenly spaced on a ring.
    Resulting array contains n points along the first axis.
    samples[0] is not (0, 0).

    Parameters
    ----------
    radius : float
        Total sampling radius.
    n : int
        Point density.

    Returns
    -------
    samples : np.ndarray of shape (n, 2)
    """
    _check_args(radius, n)

    angle = np.linspace(0, 2 * np.pi, n, endpoint=False)
    x_samples = radius * np.cos(angle)
    y_samples = radius * np.sin(angle)

    return np.column_stack((x_samples, y_samples))
