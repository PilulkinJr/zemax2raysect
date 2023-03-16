"""Reproduction of OpticsStudio's Spot Diagram."""
from typing import Literal

import numpy as np
from matplotlib.axes import Axes


class SpotDiagram:
    """Reproduction of the OpticsStudio's Spot Diagram."""

    def __init__(
        self: "SpotDiagram",
        points: np.ndarray,
        reference: Literal["vertex", "centroid"] = "centroid",
    ) -> None:
        """Initialize an instance of SpotDiagram.

        Parameters
        ----------
        points : np.ndarray
        """
        self._reference = reference
        self._points = np.array(points, dtype=float)
        self._calc_parameters()

    def _calc_reference_point(self: "SpotDiagram") -> None:

        if self._reference == "centroid":
            return np.mean(self._points, axis=0)

        if self._reference == "vertex":
            return np.zeros((1, 2), dtype=float)

        raise ValueError

    @property
    def reference(self: "SpotDiagram") -> str:
        return self._reference

    @reference.setter
    def reference(self: "SpotDiagram", value: str) -> None:
        self._reference = value
        self._calc_parameters()

    @property
    def points(self: "SpotDiagram") -> np.ndarray:
        return self._points

    @points.setter
    def points(self: "SpotDiagram", value: np.ndarray) -> None:
        self._points = value
        self._calc_parameters()

    def _calc_parameters(self: "SpotDiagram") -> None:
        self._reference_point = self._calc_reference_point()

        self._center = np.mean(self._points, axis=0)

        self._rms_radius = np.sqrt(
            np.mean(np.sum((self._points - self._reference_point) ** 2, axis=1))
        )

        self._geo_radius = np.max(
            np.sqrt(np.sum((self._points - self._reference_point) ** 2, axis=1))
        )

        self._rms_width = np.sqrt(
            np.sum((self._points - self._reference_point) ** 2, axis=0) / self._points.shape[0]
        )

        self._geo_width = np.ptp((self._points - self._reference_point), axis=0)

    @property
    def center(self: "SpotDiagram") -> np.ndarray:
        """Center of the distribution."""
        return self._center

    @property
    def rms_width(self: "SpotDiagram") -> np.ndarray:
        """RMS width of the distribution along X and Y axes."""
        return self._rms_width

    @property
    def geo_width(self: "SpotDiagram") -> np.ndarray:
        """Width of the distribution along X and Y axes."""
        return self._geo_width

    @property
    def rms_radius(self: "SpotDiagram") -> np.ndarray:
        """RMS radius of the distribution."""
        return self._rms_radius

    @property
    def geo_radius(self: "SpotDiagram") -> np.ndarray:
        """GEO radius of the distribution."""
        return self._geo_radius

    def report(self: "SpotDiagram") -> str:
        """Generate report width distribution parameters.

        Returns
        -------
        str
            Multiline text report.
        """
        rows = (
            ("Center (mm)", f"{self.center[0] * 1.0e3:0.2e}", f"{self.center[1] * 1.0e3:0.2e}"),
            ("RMS Radius (µm)", f"{self.rms_radius * 1.0e6:0.2f}"),
            ("GEO Radius (µm)", f"{self.geo_radius * 1.0e6:0.2f}"),
            (
                "RMS Width (µm)",
                f"{self.rms_width[0] * 1.0e6:0.2f}",
                f"{self.rms_width[1] * 1.0e6:0.2f}",
            ),
            (
                "GEO Width (µm)",
                f"{self.geo_width[0] * 1.0e6:0.2f}",
                f"{self.geo_width[1] * 1.0e6:0.2f}",
            ),
        )

        return "\n".join((" ".join(columns) for columns in rows))

    def plot(
        self: "SpotDiagram",
        axes: Axes,
        scale: float = 0,
        report: bool = True,
        **plot_kwargs,
    ) -> None:
        """Plot the spot diagram onto an axes.

        Parameters
        ----------
        axes : matplotlib.axes.Axes
        scale : float, default = 0
            Scale of the plot in µm. Value of 0 sets automatic limits.
        report : bool, default = True
            Print report onto the axes.
        plot_kwargs :
            Additional keyword arguments for axes.plot().

        Returns
        -------
        None
        """
        axes.plot(
            *(self.points - self.center).T * 1.0e6,
            linestyle="none",
            marker=".",
            markersize=1,
            **plot_kwargs,
        )

        axes.set_aspect(1)
        axes.set_box_aspect(1)

        if scale > 0:
            axes.set_xlim(-0.5 * scale, 0.5 * scale)
            axes.set_ylim(-0.5 * scale, 0.5 * scale)
            axes.set_xticklabels([])
            axes.set_yticklabels([])
            axes.set_xticks(np.linspace(-0.5 * scale, 0.5 * scale, 11))
            axes.set_yticks(np.linspace(-0.5 * scale, 0.5 * scale, 11))
            axes.set_ylabel(f"{scale:0.1f}")

        if report:
            axes.text(
                0.01,
                0.01,
                self.report(),
                ha="left",
                va="bottom",
                fontsize="small",
                transform=axes.transAxes,
            )
