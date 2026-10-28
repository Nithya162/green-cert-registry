# Dataset

We use the public **Solar Power Generation Data** dataset from Kaggle:
https://www.kaggle.com/datasets/anikannal/solar-power-generation-data

It contains generation data (AC/DC power, daily yield) and weather sensor data
(irradiance, ambient and module temperature) for two solar plants, which we use
as two simulated producers.

**Setup:** download the four CSV files and place them in this folder.
CSV files are ignored by Git (see `.gitignore`) to keep the repository small.

Fake readings for evaluation (power at night, doubled output, sudden spikes)
are generated from this data by `inject_fake_readings()` in `data-checker/checker.py`.
