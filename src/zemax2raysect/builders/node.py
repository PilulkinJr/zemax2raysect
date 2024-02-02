"""Builder class for optical Node."""
import logging
from typing import Literal, Sequence, Union

from raysect.core import AffineMatrix3D, Node, translate
from raysect.optical import Material

from ..surface import CoordinateBreak, Surface
from .abstract import AbstractLensBuilder, AbstractMirrorBuilder
from .common import CannotCreatePrimitive, Direction, sign

LOGGER = logging.getLogger(__name__)


class OpticalNodeBuilder:
    """Builder class for an optical node.

    Optical node is a raysect.core.Node which contains some optical elements.
    """

    def __init__(self: "OpticalNodeBuilder") -> None:
        self._clear_parameters()

    def _clear_parameters(self: "OpticalNodeBuilder") -> None:
        self._current_transform = AffineMatrix3D()
        self._current_direction: Direction = 1
        self._mirrors_passed: int = 0
        self._keep_empty_surfaces: Union[bool, Literal["image"]] = False
        self._transmission_only: bool = False

    def build(
        self: "OpticalNodeBuilder",
        surfaces: Sequence[Surface],
        *,
        materials: dict[str, Material] = None,
        keep_empty_surfaces: bool = False,
        transmission_only: bool = False,
    ) -> Node:
        """Build an optical node from a sequence of surfaces.

        Parameters
        ----------
        surfaces : Sequence of Surface
        materials: dict, default None
            User-provided dictionary mapping Zemax materials to Raysect materials.
            Searches for material by surface name, and, if not found, by surface material name.
        keep_empty_surfaces : {False, True, "image"}, default = False
            If True, create a primitive even if "Glass" for it is not set.
            "image" -- create such primitive only for image surface (the last one).
            Thickness of such surfaces is still accounted for.
        transmission_only : bool, default = False
            Set 'transmission_only' parameter to this value for all materials
            that has this parameter.

        Returns
        -------
        raysect.core.Node
        """
        self._clear_parameters()

        if not all(isinstance(s, Surface) for s in surfaces):
            raise TypeError(f"All elements of 'surfaces' must be {Surface}")

        if materials and not all(isinstance(key, str) and isinstance(val, Material) for key, val in materials.items()):
            raise TypeError(f"All elements of 'materials' must be {Surface}")

        if keep_empty_surfaces not in (False, True, "image"):
            raise ValueError(
                f"'keep_empty_surfaces' must be one of {(False, True, 'image')}"
                f", got {keep_empty_surfaces}"
            )
        self._keep_empty_surfaces = keep_empty_surfaces

        if not isinstance(transmission_only, bool):
            raise TypeError(f"'transmission_only' must be {bool}, got {type(transmission_only)}")
        self._transmission_only = transmission_only

        node = Node()
        n_surfaces = len(surfaces)
        idx = 0

        LOGGER.debug("Total number of surfaces: %i", n_surfaces)

        while idx < n_surfaces:

            LOGGER.debug("Current transform: %s", self._current_transform)

            current_surface = surfaces[idx]

            if self._process_coordinate_break(current_surface):
                LOGGER.debug("Surface %i is a CoordinateBreak", idx)
                LOGGER.debug("Moving to the next surface")
                idx += 1
                continue

            if not current_surface.material:
                if self._keep_empty_surfaces == "image" and idx == n_surfaces - 1:
                    LOGGER.debug("Creating an image surface")
                    pass

                elif idx != n_surfaces - 1 or self._keep_empty_surfaces is False:
                    LOGGER.debug("Surface %i has no material assigned, skipping it", idx)
                    if not self._process_inf_thickness(current_surface):
                        self._current_transform *= translate(0, 0, current_surface.thickness)
                    idx += 1
                    continue

                if self._keep_empty_surfaces is True:
                    LOGGER.debug("Surface %i has no material assigned, keeping it", idx)
                    pass

            if self._process_inf_thickness(current_surface):
                LOGGER.debug("Surface %i has infinite thickness", idx)
                LOGGER.debug("Moving to the next surface")
                idx += 1
                continue

            material = None
            if materials:
                # search for custom material by surface name
                if current_surface.name in materials:
                    material = materials[current_surface.name]
                # search for custom material by surface material name
                elif current_surface.material and current_surface.material in materials:
                    material = materials[current_surface.material]

            if idx + 1 < n_surfaces and not isinstance(surfaces[idx + 1], CoordinateBreak):

                next_surface = surfaces[idx + 1]

                if self._build_lens(current_surface, next_surface, node, material):

                    LOGGER.info(
                        "Surfaces %i and %i: a %s has been created",
                        idx,
                        idx + 1,
                        type(node.children[-1]),
                    )
                    idx += 1

                    # two surfaces define just one lens, skipping next surface
                    if not next_surface.material:
                        idx += 1

                    continue

            if self._build_mirror(current_surface, self._current_direction, node, material):
                LOGGER.info("Surface %i: a %s has been created", idx, type(node.children[-1]))
                idx += 1
            else:
                if hasattr(self, "_last_exception"):
                    raise self._last_exception

            # LOGGER.debug(
            #     "Direction after surface %i: %i",
            #     idx,
            #     self._current_direction,
            # )
            # LOGGER.debug(
            #     "Number of mirrors passed after surafce %i: %i",
            #     idx,
            #     self._mirrors_passed,
            # )
            # LOGGER.debug("Moving to the next surface")

        self._set_transmission_only(node)

        return node

    def _process_coordinate_break(self: "OpticalNodeBuilder", surface: Surface) -> bool:

        if not isinstance(surface, CoordinateBreak):
            return False

        self._current_transform *= surface.matrix * translate(0, 0, surface.thickness)

        if surface.thickness != 0:
            self._current_direction = sign(surface.thickness)
            LOGGER.debug("direction set to %i", self._current_direction)

        # self._current_surface_idx += 1
        # LOGGER.debug("Current surface index changed")

        return True

    def _process_empty_surface(self: "OpticalNodeBuilder", surface: Surface) -> bool:

        if self._keep_empty_surfaces in (False, "image") and not surface.material:
            self._current_transform *= translate(0, 0, surface.thickness)
            return True

        return False

    def _process_inf_thickness(self: "OpticalNodeBuilder", surface: Surface) -> bool:
        if surface.thickness != float("inf"):
            return False

        # self._current_surface_idx += 1
        # LOGGER.debug("Current surface index changed")

        return True

    def _process_mirror(self: "OpticalNodeBuilder", surface: Surface) -> bool:
        if surface.material != "MIRROR":
            return False

        self._mirrors_passed += 1

        if self._mirrors_passed % 2 == 1:
            self._current_direction *= -1

        LOGGER.debug("number of mirrors passed: %i", self._mirrors_passed)

        return True

    def _set_transmission_only(self: "OpticalNodeBuilder", node: Node) -> None:
        for child in node.children:
            if hasattr(child.material, "transmission_only"):
                child.material.transmission_only = self._transmission_only

    def _build_mirror(
        self: "OpticalNodeBuilder",
        current_surface: Surface,
        direction: Direction,
        parent_node: Node,
        material: Material = None,
    ) -> bool:

        for mirror_type in AbstractMirrorBuilder.builders:

            try:
                # LOGGER.debug("Trying to build a %s mirror from %s", mirror_type, current_surface)
                mirror = AbstractMirrorBuilder.build(mirror_type, current_surface, direction, material)

            except CannotCreatePrimitive as exception:
                self._last_exception = exception
                continue

            mirror.parent = parent_node
            mirror.transform = self._current_transform * mirror.transform

            self._current_transform *= translate(0, 0, current_surface.thickness)

            self._process_mirror(current_surface)

            return True

        else:
            return False

    def _build_lens(
        self: "OpticalNodeBuilder",
        current_surface: Surface,
        next_surface: Surface,
        parent_node: Node,
        material: Material = None,
    ) -> bool:

        for lens_type in AbstractLensBuilder.builders:

            try:
                lens = AbstractLensBuilder.build(lens_type, current_surface, next_surface, material)

            except CannotCreatePrimitive:
                continue

            lens.parent = parent_node
            lens.transform = self._current_transform * lens.transform

            # next surface having a material signals of a next lens in an assembly
            # make put some space between them
            if next_surface.material:
                padding = current_surface.thickness * 1.0e-6
                self._current_transform *= translate(0, 0, current_surface.thickness + padding)
            # two surfaces define just one lens
            # its only contribution is its thickness
            else:
                self._current_transform *= translate(
                    0, 0, current_surface.thickness + next_surface.thickness
                )

            self._process_mirror(current_surface)

            return True

        else:
            return False


def create_optical_node(
    surfaces: Sequence[Surface],
    *,
    materials: dict[str, Material] = None,
    keep_empty_surfaces: bool = False,
    transmission_only: bool = False,
) -> Node:
    return OpticalNodeBuilder().build(
        surfaces,
        materials=materials,
        keep_empty_surfaces=keep_empty_surfaces,
        transmission_only=transmission_only,
    )


def set_node_global_reference(node: Node, idx: int) -> Node:
    transform = node.children[idx].to_root().inverse()
    for child in node.children:
        child.transform = transform * child.transform
    return node
