"""Routines related to surface material proecssing."""
import logging

from raysect.core import Material
from raysect.optical import ConstantSF
from raysect.optical.library import schott
from raysect.optical.material import Dielectric, NullMaterial, Sellmeier
from raysect.optical.material.debug import PerfectReflectingSurface

LOGGER = logging.getLogger(__name__)

# Sellmeier coefficients for fused silica were copied from Zemax catalogue
MATERIALS = {
    "MIRROR": PerfectReflectingSurface(),
    "F_SILICA": Dielectric(
        Sellmeier(0.6961663, 0.4079426, 0.8974794, 4.6791480e-3, 1.3512063e-2, 97.9340025),
        ConstantSF(1.0),
    ),
}


class CannotFindMaterial(Exception):
    """Raise this exception if primitive cannot be assigned an appropriate material."""

    pass


def find_material(name: str) -> Material:
    """Find a Raysect Material appropriate to Zemax Glass.

    Tries to match a glass name with Raysect's Schott catalogue.

    Parameters
    ----------
    name : str
        Name of the material (Glass).

    Returns
    -------
    Material
    """
    if not name:
        return NullMaterial()

    if name.upper() in MATERIALS:
        return MATERIALS[name]

    if name.upper() in schott._schott_glass_data:
        return schott(name)

    for catalogue_name in schott._schott_glass_data:
        if name.lower() in catalogue_name.lower() or catalogue_name.lower() in name.lower():
            LOGGER.warning(
                f"Cannot find excact material for {name}" f", using {catalogue_name} instead"
            )
            return schott(catalogue_name)

    raise CannotFindMaterial(f"Cannot find appropriate material for {name}")
