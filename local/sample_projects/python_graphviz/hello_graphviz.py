"""https://graphviz.org/Gallery/directed/hello.html"""

import graphviz
import platform

g = graphviz.Digraph('G', filename='hello.gv', format='png')

g.edge('Hello', 'World')

g.view()
