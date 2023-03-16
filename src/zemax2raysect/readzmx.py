"""Read ZMX file."""
import logging
from collections import namedtuple
from pathlib import Path
from typing import List, Optional, Tuple

from .field import Fields, read_fields
from .surface import AbstractSurfaceBuilder, Surface, SurfaceDescription

LOGGER = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO)
logging.getLogger("matplotlib").setLevel(logging.WARNING)


Wavelength = namedtuple("Wavelength", ["n", "value", "weight"])


class ZMXreader:
    """Reader class for ZMX files."""

    def determine_encoding(self: "ZMXreader", path: str) -> Optional[str]:
        """Determine encoding of the ZMX file.

        Usually it is utf-16.

        Parameters
        ----------
        path : str

        Returns
        -------
        str or None

        """
        encodings = ("utf-8", "utf-16")

        for encoding in encodings:
            with open(path, mode="r", encoding=encoding) as file:
                try:
                    file.readline()
                except UnicodeDecodeError:
                    continue
                else:
                    return encoding

        return None

    @staticmethod
    def read_wavelengths(lines: List[str]) -> Tuple[Wavelength]:
        """Read a section of the ZMX file related to wavelengths.

        Parameters
        ----------
        lines : list of str

        Returns
        -------
        tuple of Wavelength
        """
        wavelengths: List[Wavelength] = []

        for _, line in enumerate(lines):

            columns = line.strip().split()
            cmd = columns[0]

            if cmd != "WAVM":
                return wavelengths

            # columns[1] is a wavelength ID
            # columns[2] is a wavelength in µm
            # value = float(columns[2]) * 1.0e3

            wavelength = Wavelength(
                n=int(columns[1]),
                value=float(columns[2]) * 1.0e3,
                weight=float(columns[3]),
            )

            if wavelength.value not in (wavelength.value for wavelength in wavelengths):
                wavelengths.append(wavelength)

        return tuple(wavelengths)

    def read(self: "ZMXreader", path: str) -> List[Surface]:
        """Read a ZMX file.

        Parameters
        ----------
        path : str

        Returns
        -------
        list of Surface
        """
        path = Path(path).absolute()
        LOGGER.debug("Opening file %s", path)

        if not path.exists():
            LOGGER.error("File %s does not exist", path)

        self.path = path
        self.encoding = self.determine_encoding(path)
        self.contents: List[str]
        self.surfaces = []
        self.wavelengths = []
        self.fields = Fields([])

        with open(path, mode="r", encoding=self.encoding) as file:
            self.contents = file.readlines()

        builder = AbstractSurfaceBuilder()
        unit_converion_factor = 1.0

        for i, line in enumerate(self.contents):

            columns = line.strip().split()
            if not columns:
                continue

            cmd = columns[0]
            values = columns[1:]

            if cmd == "UNIT" and values[0] == "MM":
                unit_converion_factor = 1.0e-3

            if cmd == "WAVM" and not self.wavelengths:
                self.wavelengths = self.read_wavelengths(self.contents[i:])

            if cmd == "FTYP":
                self.fields = read_fields(self.contents[i : i + 11], unit_converion_factor)

            if cmd == "SURF":
                surface_description = SurfaceDescription.fromlines(self.contents[i:])
                surface = builder.create(surface_description, unit_converion_factor)
                self.surfaces.append(surface)

        if not self.surfaces:
            raise RuntimeError("Cannot get any surfaces from %s", path)

        return self.surfaces


def readzmx(path: str) -> List[Surface]:
    """Read a ZMX file and resurn a list of surfaces.

    Parameters
    ----------
    path : str

    Returns
    -------
    list of Surface
    """
    return ZMXreader().read(path)
