#!/usr/bin/env python3
"""
Patch Runner - Discovers and applies all patches in the patches/ directory.

Each patch file should:
1. Be named with pattern: NN_patch_name.py (e.g., 01_null_traces.py)
2. Have a main() function that returns True on success, False on failure
3. Have a DESCRIPTION variable explaining what the patch does

Patches are applied in alphabetical order (hence the NN_ prefix for ordering).
"""

import importlib.util
import sys
from pathlib import Path


def load_patch_module(patch_path: Path):
    """Dynamically load a patch module from file path."""
    spec = importlib.util.spec_from_file_location(patch_path.stem, patch_path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    # Find patches directory (same directory as this script)
    script_dir = Path(__file__).parent
    patches_dir = script_dir / "patches"
    
    if not patches_dir.exists():
        print(f"ERROR: Patches directory not found: {patches_dir}")
        return 1
    
    # Find all patch files, sorted by name
    patch_files = sorted(patches_dir.glob("*.py"))
    
    if not patch_files:
        print("No patches found in patches/ directory")
        return 0
    
    print("=" * 60)
    print("CRYO PATCH RUNNER")
    print("=" * 60)
    print(f"Found {len(patch_files)} patch(es) to apply\n")
    
    failed_patches = []
    applied_patches = []
    skipped_patches = []
    
    for patch_file in patch_files:
        patch_name = patch_file.stem
        print(f"\n{'─' * 60}")
        print(f"PATCH: {patch_name}")
        print(f"{'─' * 60}")
        
        try:
            module = load_patch_module(patch_file)
            
            # Print description if available
            if hasattr(module, 'DESCRIPTION'):
                print(f"Description: {module.DESCRIPTION}")
            
            # Check if patch has a main function
            if not hasattr(module, 'main'):
                print(f"WARNING: {patch_name} has no main() function, skipping")
                skipped_patches.append(patch_name)
                continue
            
            # Apply the patch
            result = module.main()
            
            if result is True:
                print(f"✓ {patch_name} applied successfully")
                applied_patches.append(patch_name)
            elif result == "skipped":
                print(f"○ {patch_name} skipped (already applied)")
                skipped_patches.append(patch_name)
            else:
                print(f"✗ {patch_name} failed")
                failed_patches.append(patch_name)
                
        except Exception as e:
            print(f"✗ {patch_name} failed with exception: {e}")
            failed_patches.append(patch_name)
    
    # Summary
    print(f"\n{'=' * 60}")
    print("PATCH SUMMARY")
    print(f"{'=' * 60}")
    print(f"Applied:  {len(applied_patches)}")
    print(f"Skipped:  {len(skipped_patches)}")
    print(f"Failed:   {len(failed_patches)}")
    
    if failed_patches:
        print(f"\nFailed patches: {', '.join(failed_patches)}")
        return 1
    
    print("\nAll patches processed successfully!")
    return 0


if __name__ == "__main__":
    sys.exit(main())