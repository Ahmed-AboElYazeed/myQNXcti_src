"""https://graphviz.org/Gallery/directed/hello.html"""

import graphviz

from graphviz import Source

g = Source.from_file('python3.gv')
g.format = 'png'

g.view()
