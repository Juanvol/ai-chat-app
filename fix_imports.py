#!/usr/bin/env python3
"""修正 Phase B 目录重构后的所有 import 路径。"""
import os
import re
from pathlib import Path

LIB = Path(r'c:\Users\lenovo\Desktop\ai-chat-app\lib').resolve()

def norm(p):
    """Normalize path to forward slashes, resolved."""
    return str(Path(p).resolve()).replace('\\', '/')

# old_path (relative to lib/) → new_path (relative to lib/)
MOVES = {
    'pet/pet_state.dart': 'models/pet_state.dart',
    'services/conversation_service.dart': 'services/app/conversation_service.dart',
    'services/feedback_service.dart': 'services/app/feedback_service.dart',
    'services/memory_service.dart': 'services/app/memory_service.dart',
    'services/persona_service.dart': 'services/app/persona_service.dart',
    'services/storage_service.dart': 'services/app/storage_service.dart',
    'services/token_stats_service.dart': 'services/app/token_stats_service.dart',
    'services/pet_agent_core.dart': 'services/pet/pet_agent_core.dart',
    'services/pet_ai_service.dart': 'services/pet/pet_ai_service.dart',
    'services/pet_brain.dart': 'services/pet/pet_brain.dart',
    'services/pet_bubble_manager.dart': 'services/pet/pet_bubble_manager.dart',
    'services/pet_chat_service.dart': 'services/pet/pet_chat_service.dart',
    'services/pet_diary_service.dart': 'services/pet/pet_diary_service.dart',
    'services/pet_feature_flags.dart': 'services/pet/pet_feature_flags.dart',
    'services/pet_logger.dart': 'services/pet/pet_logger.dart',
    'services/pet_overlay_host.dart': 'services/pet/pet_overlay_host.dart',
    'services/pet_profile_service.dart': 'services/pet/pet_profile_service.dart',
    'services/pet_service.dart': 'services/pet/pet_service.dart',
    'services/pet_token_service.dart': 'services/pet/pet_token_service.dart',
    'screens/pet_center_screen.dart': 'screens/pet/pet_center_screen.dart',
    'screens/pet_chat_screen.dart': 'screens/pet/pet_chat_screen.dart',
    'screens/pet_diary_screen.dart': 'screens/pet/pet_diary_screen.dart',
    'screens/pet_memory_screen.dart': 'screens/pet/pet_memory_screen.dart',
    'screens/pet_settings_screen.dart': 'screens/pet/pet_settings_screen.dart',
    'widgets/pet_action_bar.dart': 'widgets/pet/pet_action_bar.dart',
    'widgets/pet_hero_card.dart': 'widgets/pet/pet_hero_card.dart',
    'widgets/pet_info_chips.dart': 'widgets/pet/pet_info_chips.dart',
    'widgets/pet_status_bars.dart': 'widgets/pet/pet_status_bars.dart',
}

# old normalized absolute path → new normalized absolute path
OLD_ABS_TO_NEW = {}
for old_rel, new_rel in MOVES.items():
    OLD_ABS_TO_NEW[norm(LIB / old_rel)] = norm(LIB / new_rel)

# Set of all existing .dart files (normalized)
ALL_DART = set()
for root, dirs, files in os.walk(str(LIB)):
    for f in files:
        if f.endswith('.dart'):
            ALL_DART.add(norm(Path(root) / f))

def rel_import(from_dir, to_abs):
    """Compute relative import path from from_dir to to_abs (normalized)."""
    try:
        rel = os.path.relpath(to_abs, from_dir).replace('\\', '/')
        if not rel.startswith('.'):
            rel = './' + rel
        return rel
    except ValueError:
        return None

def find_real_target(file_dir, import_path):
    """
    Try to find the real target of an import.
    Returns (real_abs_path, import_to_use) or (None, None).
    Tries up to 5 levels of '../' prefix.
    """
    file_dir_norm = norm(file_dir)
    for depth in range(6):
        if depth == 0:
            candidate_import = import_path
        else:
            candidate_import = '../' * depth + import_path

        target_abs = norm(Path(file_dir) / candidate_import)

        # Check if target exists directly
        if target_abs in ALL_DART:
            return target_abs, candidate_import

        # Check if target is an old path that has been moved
        if target_abs in OLD_ABS_TO_NEW:
            new_target_abs = OLD_ABS_TO_NEW[target_abs]
            new_import = rel_import(file_dir_norm, new_target_abs)
            if new_import:
                return new_target_abs, new_import

    return None, None

def fix_package_import(import_path):
    """Fix package:deepseek_chat/... imports by checking MOVES mapping."""
    if not import_path.startswith('package:deepseek_chat/'):
        return import_path
    relative = import_path[len('package:deepseek_chat/'):]
    if relative in MOVES:
        return 'package:deepseek_chat/' + MOVES[relative]
    return import_path

def fix_file(file_path):
    file_dir = str(file_path.parent)
    content = file_path.read_text(encoding='utf-8')
    modified = False

    def replace_import(match):
        nonlocal modified
        prefix = match.group(1)
        import_path = match.group(2)

        if import_path.startswith('dart:'):
            return match.group(0)

        # Handle package:deepseek_chat/... imports
        if import_path.startswith('package:deepseek_chat/'):
            new_pkg = fix_package_import(import_path)
            if new_pkg != import_path:
                modified = True
                return f"{prefix} '{new_pkg}'"
            return match.group(0)

        # Skip other package: imports
        if import_path.startswith('package:'):
            return match.group(0)

        real_target, new_import = find_real_target(file_dir, import_path)

        if real_target is None:
            return match.group(0)

        if new_import != import_path:
            modified = True
            return f"{prefix} '{new_import}'"

        return match.group(0)

    new_content = re.sub(
        r"(import|export) '([^']+)'",
        replace_import,
        content
    )

    if new_content != content:
        file_path.write_text(new_content, encoding='utf-8')
        return True
    return False

# ── Run ──
fixed_count = 0
PROJECT = LIB.parent
dart_files = list(PROJECT.rglob('*.dart'))
print(f"Scanning {len(dart_files)} Dart files...\n")

for fp in sorted(dart_files):
    if fix_file(fp):
        rel = fp.relative_to(PROJECT)
        print(f"  FIX: {rel}")
        fixed_count += 1

print(f"\n{'='*50}")
print(f"Fixed {fixed_count} files.")
print(f"{'='*50}")
