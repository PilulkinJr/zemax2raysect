# -*- coding: utf-8 -*-
from setuptools import setup

package_dir = {"": "src"}

packages = [
    "zemax2raysect",
    "zemax2raysect.analysis",
    "zemax2raysect.primitive",
    "zemax2raysect.primitive.cylindrical",
    "zemax2raysect.primitive.spherical",
    "zemax2raysect.primitive.toric",
    "zemax2raysect.utility",
]

package_data = {"": ["*"]}

install_requires = ["numpy==1.19.4", "raysect==0.7.1"]

setup_kwargs = {
    "name": "zemax2raysect",
    "version": "0.1.0",
    "description": "Convert Zemax' ZMX file into a Raysect Node",
    "long_description": "# Zemax2Raysect\n\nThe aim of this library to translate projects developed in Zemax OpticsStudio into Raysect's primitives.\n\n## Installation\n\nFront the project's root folder:\n\n```sh\npip install .\n```\n\nor directly using `setup.py`:\n\n```sh\npython setup.py install\n```\n\n## Usage\n\n### Limitations\n\n* Only sequential mode is available;\n* The first surface has to be set as global reference;\n* All elements are going to have a round frame with radius equal to surface's Semi-Diameter. Some flat surface object can have rectangular shape if Aperture Decenter is zero along both axes.\n\nAvailable objects:\n\n* All types of spherical lenses;\n* Plano-convex and -concave cylindrical lenses;\n* Spherical and toric mirrors.\n\n### Node\n\n```python\nfrom raysect.optical import World\nfrom zemax2raysect.readzmx import readzmx, create_node_from_surfaces\n\nsurfaces = readzmx(\"MICROSCOPE.ZMX\")\n\nworld = World()\nnode = create_node_from_surfaces(surfaces, transmission_only=True)\nnode.parent = world\n```\n\n### Single object\n\n```python\nfrom raysect.optical import World\nfrom zemax2raysect.readzmx import readzmx\nfrom zemax2raysect.builders import create_spherical_lens\n\nsurfaces = readzmx(\"MICROSCOPE.ZMX\")\n\nworld = World()\nlens = create_spherical_lens(surfaces[0], surfaces[1])  # back and front surfaces\nlens.parent = world\n```\n\n## Development\n\nThis project is packaged using Poetry and can be installed by it:\n```sh\npoetry install\n```\n\nAlternatively, using `pip`:\n```sh\npip install -e .\n```\nor\n```sh\npython setup.py develop\n```\n\nTo rebuild Cython extensions use\n```sh\npython setup.py build_ext --inplace\n```\n\n*Note: don't use `build.py`. It is already incorporated into `setup.py` created by Poetry.*\n",
    "author": "Aleksei Shabashov",
    "author_email": "a.shabashov@iterrf.ru",
    "maintainer": "None",
    "maintainer_email": "None",
    "url": "None",
    "package_dir": package_dir,
    "packages": packages,
    "package_data": package_data,
    "install_requires": install_requires,
    "python_requires": ">=3.8,<4.0",
}
from build import *

build(setup_kwargs)

setup(**setup_kwargs)
