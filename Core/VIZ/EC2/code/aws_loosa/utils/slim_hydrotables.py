import pandas as pd
import os

configuration = "fr"
fim_version = "3_0_28_1"

data_folder = f"/dev_fim_share/foss_fim/previous_fim/fim_3_0_28_1_fr/aggregate_fim_outputs/{configuration}_{fim_version}"
workspace = "/home/corey.krewson/"

for huc in os.listdir(data_folder):
    hydrotable = os.path.join(data_folder, huc, "hydroTable.csv")
    new_hydrotable = os.path.join(workspace, huc, "hydroTable.csv")
    print(f"Processing {hydrotable}")
    df = pd.read_csv(hydrotable)
    df = df[["HydroID", "feature_id", "stage", "LakeID", "discharge_cms"]]
    df.to_csv(new_hydrotable, index=False)