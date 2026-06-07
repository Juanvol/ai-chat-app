#!/usr/bin/env python3
"""Replace hardcoded pet self-reference with dynamic PersonaStore reads."""
import os, re

SERVICE_FILES = [
    'lib/services/pet/pet_bubble_manager.dart',
    'lib/services/pet/pet_diary_service.dart',
    'lib/services/pet/pet_brain.dart',
    'lib/services/pet/pet_agent_core.dart',
    'lib/services/pet/pet_ai_service.dart',
    'lib/services/pet/knowledge/diary/diary_store.dart',
    'lib/services/pet/knowledge/memory/memory_extractor.dart',
]

UI_FILES = [
    'lib/screens/pet/pet_record_screen.dart',
    'lib/screens/pet/pet_suggestion_screen.dart',
    'lib/screens/pet/pet_settings_screen.dart',
    'lib/screens/pet/pet_chat_history_screen.dart',
    'lib/screens/pet/pet_center_screen.dart',
    'lib/widgets/home_drawer.dart',
]

def add_import(lines, import_line, check_str):
    if check_str in '\n'.join(lines):
        return lines
    insert_at = 0
    for i, line in enumerate(lines):
        if line.startswith('import '):
            insert_at = i
    lines.insert(insert_at + 1, import_line)
    return lines

for filepath in SERVICE_FILES:
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
        count = content.count('糯糯')
        if count == 0:
            continue
        replacement = "${PetPersona().style.selfReference}"
        content = content.replace('糯糯', replacement)
        lines = content.split('\n')
        rel = os.path.relpath('lib/pet/pet_persona.dart', os.path.dirname(filepath)).replace('\\', '/')
        import_line = f"import '{rel}';"
        lines = add_import(lines, import_line, "import '")
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write('\n'.join(lines))
        print(f'{filepath}: replaced {count}')
    except Exception as e:
        print(f'{filepath}: ERROR {e}')

for filepath in UI_FILES:
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
        count = content.count('糯糯')
        if count == 0:
            continue
        replacement = "${petOverlayController.personaStore?.persona.style.selfReference ?? '糯糯'}"
        content = content.replace('糯糯', replacement)
        lines = content.split('\n')
        rel = os.path.relpath('lib/services/pet/pet_overlay_host.dart', os.path.dirname(filepath)).replace('\\', '/')
        import_line = f"import '{rel}';"
        lines = add_import(lines, import_line, "import '")
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write('\n'.join(lines))
        print(f'{filepath}: replaced {count}')
    except Exception as e:
        print(f'{filepath}: ERROR {e}')

print('Done')
