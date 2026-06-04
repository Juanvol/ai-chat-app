from pathlib import Path
import os
import re

LIB = Path(r'c:\Users\lenovo\Desktop\ai-chat-app\lib').resolve()

MOVES = {'pet/pet_state.dart': 'models/pet_state.dart'}
OLD_ABS_TO_NEW = {}
for old_rel, new_rel in MOVES.items():
    OLD_ABS_TO_NEW[str(LIB / old_rel)] = str(LIB / new_rel)

def norm(p):
    return str(Path(p).resolve()).replace('\\', '/')

ALL_DART = set()
for root, dirs, files in os.walk(str(LIB)):
    for f in files:
        if f.endswith('.dart'):
            ALL_DART.add(str(Path(root) / f))

print('OLD_ABS_TO_NEW:')
for k, v in OLD_ABS_TO_NEW.items():
    print(f'  {k} -> {v}')

file_dir = str(LIB / 'services/pet')
import_path = '../pet/pet_state.dart'

for depth in range(4):
    if depth == 0:
        candidate = import_path
    else:
        candidate = '../' * depth + import_path
    target = norm(Path(file_dir) / candidate)
    in_all = target in ALL_DART
    in_old = target in OLD_ABS_TO_NEW
    print(f'\ndepth={depth}: candidate={candidate}')
    print(f'  target={target}')
    print(f'  in ALL_DART={in_all}, in OLD_ABS={in_old}')

print('\n--- ALL_DART sample ---')
for d in sorted(ALL_DART)[:5]:
    print(f'  {d}')

lib_pet_state = str(LIB / 'pet/pet_state.dart')
print(f'\nlib/pet/pet_state.dart in ALL_DART: {lib_pet_state in ALL_DART}')
lib_models_pet_state = str(LIB / 'models/pet_state.dart')
print(f'lib/models/pet_state.dart in ALL_DART: {lib_models_pet_state in ALL_DART}')
