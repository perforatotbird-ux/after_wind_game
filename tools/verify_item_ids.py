#!/usr/bin/env python3
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def verify_all_item_ids():
    print("=" * 60)
    print("VERIFYING ITEM IDs ACROSS ALL DATABASES")
    print("=" * 60)

    item_db_content = (ROOT / "scripts/inventory/item_db.gd").read_text(encoding="utf-8")
    # ITEMS = { "item_id": { ... } }
    defined_items = set(re.findall(r'^\s*"([a-zA-Z0-9_]+)":\s*\{', item_db_content, re.MULTILINE))
    print(f"Total defined items in ItemDB: {len(defined_items)}")

    # Check inventory.gd items dictionary
    inv_content = (ROOT / "scripts/inventory/inventory.gd").read_text(encoding="utf-8")
    inv_items = set(re.findall(r'^\s*"([a-zA-Z0-9_]+)":\s*0,?', inv_content, re.MULTILINE))
    print(f"Total items in inventory.gd default dictionary: {len(inv_items)}")

    missing_in_item_db = inv_items - defined_items
    if missing_in_item_db:
        print(f"  [ERROR] Items in inventory.gd but missing in ItemDB: {missing_in_item_db}")
    else:
        print("  [OK] All inventory.gd items exist in ItemDB.")

    # Check RecipeDB
    recipe_db = (ROOT / "scripts/crafting/recipe_db.gd").read_text(encoding="utf-8")
    # inputs and outputs in recipes
    recipe_inputs = set(re.findall(r'"inputs":\s*\{([^}]+)\}', recipe_db))
    missing_recipe_items = set()
    for block in recipe_inputs:
        for m in re.finditer(r'"([a-zA-Z0-9_]+)":', block):
            iid = m.group(1)
            if iid not in defined_items:
                missing_recipe_items.add(iid)
    
    recipe_outputs = set(re.findall(r'"outputs":\s*\{([^}]+)\}', recipe_db))
    for block in recipe_outputs:
        for m in re.finditer(r'"([a-zA-Z0-9_]+)":', block):
            iid = m.group(1)
            if iid not in defined_items:
                missing_recipe_items.add(iid)

    if missing_recipe_items:
        print(f"  [ERROR] Items in RecipeDB missing from ItemDB: {missing_recipe_items}")
    else:
        print("  [OK] All RecipeDB items exist in ItemDB.")

    # Check ContractDB
    contract_db = (ROOT / "scripts/economy/contract_db.gd").read_text(encoding="utf-8")
    contract_reqs = set(re.findall(r'"requirements":\s*\{([^}]+)\}', contract_db))
    missing_contract_items = set()
    for block in contract_reqs:
        for m in re.finditer(r'"([a-zA-Z0-9_]+)":', block):
            iid = m.group(1)
            if iid not in defined_items:
                missing_contract_items.add(iid)
    if missing_contract_items:
        print(f"  [ERROR] Items in ContractDB missing from ItemDB: {missing_contract_items}")
    else:
        print("  [OK] All ContractDB items exist in ItemDB.")

if __name__ == "__main__":
    verify_all_item_ids()
