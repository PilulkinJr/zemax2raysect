# Zemax2Raysect

The aim of this library to translate projects developed in Zemax OpticsStudio into Raysect's primitives.

## Installation

Front the project's root folder:

```sh
pip install .
```

or directly using `setup.py`:

```sh
python setup.py install
```

## Usage

### Limitations

* Only sequential mode is available;
* All elements are going to have a round frame with radius equal to surface's Semi-Diameter. Some flat surface object can have rectangular shape if Aperture Decenter is zero along both axes.

### Node

```python
from raysect.optical import World
from zemax2raysect import create_optical_node, readzmx

surfaces = readzmx("MICROSCOPE.ZMX")

world = World()
node = create_optical_node(surfaces, transmission_only=True)
node.parent = world
```

### Single object

```python
from raysect.optical import World
from zemax2raysect.readzmx import readzmx
from zemax2raysect.builders import create_lens

surfaces = readzmx("MICROSCOPE.ZMX")

world = World()
lens = create_lens(surfaces[0], surfaces[1])  # back and front surfaces
lens.parent = world
```

## Development

This project is packaged using Poetry and can be installed by it:
```sh
poetry install
```

Alternatively, using `pip`:
```sh
pip install -e .
```
or
```sh
python setup.py develop
```

To rebuild Cython extensions use
```sh
python setup.py build_ext --inplace
```

*Note: don't use `build.py`. It is already incorporated into `setup.py` created by Poetry.*
