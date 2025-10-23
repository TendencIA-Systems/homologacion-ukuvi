#!/usr/bin/env python3
"""
Analyze vehicle distribution by number of insurers
"""

import csv
import json
from collections import Counter

DATA_FILE = '../data/validation/catalogo_revision.csv'

def count_insurers_in_disponibilidad(disp_json_str):
    """Count how many insurers are in the disponibilidad JSON"""
    try:
        if not disp_json_str or disp_json_str.strip() == '':
            return 0

        disp = json.loads(disp_json_str)

        # Count insurers where disponible=true
        count = 0
        for insurer, data in disp.items():
            if isinstance(data, dict) and data.get('disponible', False):
                count += 1

        return count
    except:
        return 0

def main():
    print("VEHICLE DISTRIBUTION BY INSURER AVAILABILITY")
    print("=" * 80)
    print()

    insurer_counts = []
    total_records = 0

    with open(DATA_FILE, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)

        for row in reader:
            total_records += 1
            disp = row.get('disponibilidad', '')
            count = count_insurers_in_disponibilidad(disp)
            insurer_counts.append(count)

    # Count distribution
    distribution = Counter(insurer_counts)

    print(f"Total Records Analyzed: {total_records:,}\n")
    print("Number of Insurers | Vehicle Count | Percentage | Bar Chart")
    print("-" * 80)

    cumulative = 0
    for num_insurers in range(0, 12):
        count = distribution.get(num_insurers, 0)
        pct = (count / total_records) * 100 if total_records > 0 else 0
        cumulative += count

        # Create simple bar chart
        bar_length = int(pct / 2)  # Scale to max 50 chars
        bar = '█' * bar_length

        if count > 0:
            print(f"  {num_insurers:2d} insurers    | {count:13,} | {pct:6.2f}%    | {bar}")

    print("-" * 80)
    print(f"  TOTAL          | {total_records:13,} | 100.00%")
    print()

    # Summary statistics
    print("Summary Statistics:")
    print("-" * 40)

    # Calculate ranges
    exclusive_1 = distribution.get(1, 0)
    few_2_3 = distribution.get(2, 0) + distribution.get(3, 0)
    some_4_6 = sum(distribution.get(i, 0) for i in range(4, 7))
    many_7_9 = sum(distribution.get(i, 0) for i in range(7, 10))
    most_10_11 = distribution.get(10, 0) + distribution.get(11, 0)
    none_0 = distribution.get(0, 0)

    print(f"No insurers (0):            {none_0:6,} ({none_0/total_records*100:5.2f}%)")
    print(f"Exclusive (1 insurer):      {exclusive_1:6,} ({exclusive_1/total_records*100:5.2f}%)")
    print(f"Few (2-3 insurers):         {few_2_3:6,} ({few_2_3/total_records*100:5.2f}%)")
    print(f"Some (4-6 insurers):        {some_4_6:6,} ({some_4_6/total_records*100:5.2f}%)")
    print(f"Many (7-9 insurers):        {many_7_9:6,} ({many_7_9/total_records*100:5.2f}%)")
    print(f"Most (10-11 insurers):      {most_10_11:6,} ({most_10_11/total_records*100:5.2f}%)")
    print()

    # Average insurers per vehicle
    total_insurer_count = sum(num * count for num, count in distribution.items())
    avg_insurers = total_insurer_count / total_records if total_records > 0 else 0

    print(f"Average insurers per vehicle: {avg_insurers:.2f}")
    print()

    # Most common counts
    print("Most common availability levels:")
    for num_insurers, count in distribution.most_common(5):
        pct = (count / total_records) * 100
        print(f"  {num_insurers:2d} insurers: {count:6,} vehicles ({pct:5.2f}%)")

if __name__ == '__main__':
    main()
