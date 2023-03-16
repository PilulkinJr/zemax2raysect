"""Dataclass to accommodate OpticsStudio field description."""
import math
from collections import UserList
from dataclasses import dataclass
from typing import Iterable, List, Tuple


@dataclass
class Field:
    """Dataclass holding field position and vignetting factors.

    Parameters
    ----------
    field_type : int, default = 0
        Field type. 0 -- angle in degrees, 1 -- object height in meters.
    x : float, default = 0
        X-Field
    y : float, default = 0
        Y-Field
    """

    field_type: int = 0
    x: float = 0.0
    y: float = 0.0
    weight: float = 1.0
    vdx: float = 0.0
    vdy: float = 0.0
    vcx: float = 0.0
    vcy: float = 0.0
    van: float = 0.0

    def transform(self: "Field", px: float, py: float) -> Tuple[float, float]:
        """Transform pupil coordinates according to vignetting factors.

        Parameters
        ----------
        px, py : float
            Pupil coordinates.

        Returns
        -------
        px, py : (float, float)
            Modified pupil coordinates.
        """
        _px = self.vdx + px * (1 - self.vcx)
        _py = self.vdy + py * (1 - self.vcy)

        px = _px * math.cos(self.van) - _py * math.sin(self.van)
        py = _px * math.sin(self.van) + _py * math.cos(self.van)

        return px, py


class Fields(UserList):
    PARAMETERS = {
        "XFLN": "x",
        "YFLN": "y",
        "FWGN": "weight",
        "VDXN": "vdx",
        "VDYN": "vdy",
        "VCXN": "vcx",
        "VCYN": "vcy",
        "VANN": "van",
    }

    def __init__(self: "Fields", iterable: Iterable[Field]) -> None:
        super().__init__(item for item in iterable if isinstance(item, Field))
        self._field_type: int = 0

    def __setitem__(self: "Fields", index: int, item: Field) -> None:
        if isinstance(item, Field):
            self.data[index] = item

    def append(self: "Fields", item: Field) -> None:
        if isinstance(item, Field):
            self.data.append(item)

    @property
    def field_type(self: "Fields") -> None:
        """Field type.

        0 -- angle in degrees;
        1 -- object height in meters
        """
        return self._field_type

    @field_type.setter
    def field_type(self: "Fields", value: int) -> None:
        if not isinstance(value, int):
            raise TypeError(f"field_type has to be int, got {type(value)}")
        if value not in (0, 1):
            raise ValueError(f"Field type {value} is not supported")
        self._field_type = value
        for field in self.data:
            field.field_type = value

    def set_attribute(
        self: "Fields",
        name: str,
        values: Iterable[float],
        units_factor: float = 1.0,
    ) -> None:
        """Set values to a common attribute for a list of fields.

        Parameters
        ----------
        name : str
            Name of the attribute.
        values : iterable of float
        units_factor : float

        Returns
        -------
        list of Field
        """
        if not self.data:
            for _ in values:
                self.data.append(Field())

        if not hasattr(self.data[0], name):
            raise ValueError()

        # field type is an angle
        if self.field_type == 0 and name.upper() in ("XFLN", "YFLN"):
            for f, v in zip(self.data, values):
                setattr(f, name, v)
        # field type is object height -- convert it to meters
        else:
            for f, v in zip(self.data, values):
                setattr(f, name, v * units_factor)


def read_fields(lines: List[str], units_factor: float = 1.0) -> Fields:
    """Read a section of the ZMX file related to fields.

    Parameters
    ----------
    lines : list of str
    units_factor : float

    Returns
    -------
    Fields
    """
    fields = Fields([])

    columns = lines[0].strip().split()
    if columns[0] != "FTYP":
        raise ValueError(f"First line should start with 'FTYP', got {columns[0]}")

    fields.field_type = int(columns[1])
    n_fields = int(columns[3])

    for line in lines[1:]:

        columns = line.strip().split()

        cmd = columns[0]
        if cmd not in Fields.PARAMETERS:
            continue

        attr = Fields.PARAMETERS.get(cmd)
        values = map(float, columns[1 : n_fields + 1])

        if attr is not None:
            fields.set_attribute(attr, values, units_factor)

        if cmd == "VANN":
            break

    return fields
