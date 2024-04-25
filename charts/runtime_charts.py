#!/usr/bin/env python
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker
import numpy as np

categories = ["Very Large (5 GB)", "Large (1 GB)", "Medium (32 MB)", "Small (256 KB)"]
operations = ["Upload", "Download", "Same-Region Copy", "Different-Region Copy"]
bar_titles = [
    "Upload Time Comparison for 4 TBs of Data",
    "Download Time Comparison for 4 TBs of Data",
    "Same-Region Bucket Copy Time Comparison for 4 TBs of Data",
    "Different-Region Bucket Copy Time Comparison for 4 TBs of Data",
]
bar_filenames = [
    "upload_comparison.png",
    "download_comparison.png",
    "same_region_copy_comparison.png",
    "different_region_copy_comparison.png",
]

x = np.arange(len(categories))  # Label locations in bar charts
width = 0.2  # Width of the bars in bar charts

# Category + Operation data arrays in seconds, converted to minutes and then rounded
s5cmd = np.round(
    np.array(
        [
            [614, 895, 465, 4132],  # Very large
            [612, 899, 405, 3499],  # Large
            [617, 880, 335, 3656],  # Medium
            [7988, 6599, 12053, 44127],  # Small
        ]
    )
)
aws_default = np.round(
    np.array(
        [
            [11790, 13806, 17446, 120009],  # Very large
            [12835, 15078, 19465, 122780],  # Large
            [16317, 13447, 26874, 146184],  # Medium
            [185440, 201390, 332655, 1216567],  # Small
        ]
    )
)
aws_optimized = np.round(
    np.array(
        [
            [10928, 11507, 1664, 14431],  # Very large
            [10782, 5773, 1615, 16890],  # Large
            [11221, 6261, 1355, 14653],  # Medium
            [60509, 57255, 52854, 194838],  # Small
        ]
    )
)

# Bar chart for each operation
for i in range(4):
    fig, ax = plt.subplots(figsize=(10, 6))
    ax.set_yscale('log')
    bars1 = ax.bar(x - width, s5cmd[:, i], width, label="s5cmd")
    bars2 = ax.bar(x, aws_default[:, i], width, label="AWS CLI Default")
    bars3 = ax.bar(x + width, aws_optimized[:, i], width, label="AWS CLI Optimized")

    # Add annotated labels containing runtimes (rounded to the nearest second) and fold-difference from s5cmd runtime
    for j, bars in enumerate((bars1, bars2, bars3)):
        for k, bar in enumerate(bars):
            yval = int(bar.get_height())
            if j == 0:  # s5cmd bars, only show the runtime
                label = yval
            else:  # AWS bars, show both runtime and fold-difference
                fold_diff = yval / s5cmd[k, i]
                label = f"{yval}\n({fold_diff:.1f}x)"
            ax.text(
                bar.get_x() + bar.get_width() / 2,
                yval + 1,
                label,
                ha="center",
                va="bottom",
                fontsize=8,
                rotation=0,
            )

    ax.set_ylabel("Runtime (seconds)")
    ax.set_title(bar_titles[i] + "\n(AWS vs. s5cmd runtime difference shown in parentheses)")
    ax.set_xticks(x)
    ax.set_xticklabels(categories)
    ax.legend()

    fig.tight_layout()
    plt.savefig(bar_filenames[i], dpi=600)
    plt.close(fig)

# Calculate s5cmd-to-AWS performance increase ratios
ratio_default = aws_default / s5cmd
ratio_optimized = aws_optimized / s5cmd

# Combined ratio line chart
colors = ["red", "blue", "green", "purple"]
styles = ["-", "--"]  # Solid for default, dashed for optimized
plt.figure(figsize=(10, 6))
for i, operation in enumerate(operations):
    plt.plot(
        categories,
        ratio_default[:, i],
        label=f"{operation} (Default AWS CLI)",
        color=colors[i],
        linestyle=styles[0],
        marker="o",
    )
    plt.plot(
        categories,
        ratio_optimized[:, i],
        label=f"{operation} (Optimized AWS CLI)",
        color=colors[i],
        linestyle=styles[1],
        marker="o",
    )

plt.title("Runtime Improvement of 's5cmd' over 'aws s3 cp' When Moving 4 TBs")
plt.xlabel("File Size")
plt.ylabel("Runtime Ratio (AWS CLI / s5cmd)")
plt.xticks(x, categories)
plt.legend(title="Scenarios", loc="upper left", bbox_to_anchor=(1.05, 1))
plt.grid(True)

# Set the y-axis to logarithmic scale and customize ticks
plt.yscale("log")
ax = plt.gca()
ax.yaxis.set_major_locator(ticker.LogLocator(base=10.0, numticks=10))
ax.yaxis.set_major_formatter(ticker.FuncFormatter(lambda x, pos: f"{int(x)}X"))
ax.yaxis.set_minor_locator(
    ticker.FixedLocator(
        [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20, 30, 40, 50, 60, 70, 80, 100, 200]
    )
)
ax.yaxis.set_minor_formatter(ticker.FuncFormatter(lambda x, pos: f"{int(x)}X"))
plt.tight_layout()
plt.savefig("all_operations_ratio_comparison_log_scale.png", dpi=600)
plt.close()
