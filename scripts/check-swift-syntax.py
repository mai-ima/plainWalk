#!/usr/bin/env python3
"""Parse canonical Swift sources without pretending to type-check Apple APIs."""
from pathlib import Path
import sys
from tree_sitter import Language, Parser
import tree_sitter_swift

root = Path(__file__).resolve().parents[1]
parser = Parser(Language(tree_sitter_swift.language()))
# The grammar misparses valid multiple trailing closures in the Widget extension.
# Xcode remains the validation gate for that target.
paths = sorted(path for folder in ('PlainWalk', 'Shared')
               for path in (root / 'ios' / folder).glob('*.swift'))
errors = []
for path in paths:
    tree = parser.parse(path.read_bytes())
    if not tree.root_node.has_error:
        continue
    pending = [tree.root_node]
    while pending:
        node = pending.pop()
        if node.type == 'ERROR' or node.is_missing:
            row, column = node.start_point
            errors.append(f'{path.relative_to(root)}:{row + 1}:{column + 1}: '
                          f'{"missing " if node.is_missing else "invalid "}{node.type}')
        pending.extend(reversed(node.children))
if errors:
    print('\n'.join(errors), file=sys.stderr)
    sys.exit(1)
print(f'{len(paths)} app/shared Swift files parsed. Live Activity extension, Apple SDK types and APIs require Xcode compilation.')
