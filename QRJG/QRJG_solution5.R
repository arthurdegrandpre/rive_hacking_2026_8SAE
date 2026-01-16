############################################################
# EXERCICE – Prédire bird_health_index à partir d'un dataset
# Missions:
# 1) Explorer
# 2) Modéliser (technique au choix)
# 3) Importance des prédicteurs
# 4) Prédire to_predict.csv (10 individus)
############################################################


library(tidyverse)
library(skimr)
library(naniar)
library(GGally)
library(tidymodels)
library(ranger)
library(vip)

tidymodels_prefer()
set.seed(123)

# ----------------------------
# 1) Charger les données
# ----------------------------
data <- read.csv("dataset.csv", header = TRUE)
to_pred <- read.csv("to_predict.csv", header = TRUE)

# Harmoniser les noms (au cas où Bird_health_index vs bird_health_index)
# Ici, on se base sur votre énoncé: bird_health_index
# Si votre colonne s'appelle autrement, renommez-la ici.
if ("Bird_health_index" %in% names(data) && !"bird_health_index" %in% names(data)) {
  data <- data %>% rename(bird_health_index = Bird_health_index)
}

# Vérif structure
glimpse(data)
glimpse(to_pred)

# ----------------------------
# MISSION 1 – Explorer
# ----------------------------

# 1.1 Aperçu global
skimr::skim(data)

# 1.2 Taux de NA par variable
na_rate <- data %>%
  summarise(across(everything(), ~mean(is.na(.)))) %>%
  pivot_longer(everything(), names_to = "variable", values_to = "prop_NA") %>%
  arrange(desc(prop_NA))

print(na_rate)

# 1.3 Visualiser les NA (pattern)
gg_miss_var(data) + ggtitle("Proportion de valeurs manquantes par variable")

# 1.4 Résumé de la variable réponse
data %>%
  ggplot(aes(x = bird_health_index)) +
  geom_histogram(bins = 30) +
  geom_density() +
  ggtitle("Distribution de bird_health_index")

# 1.5 Relations simples (numériques)
num_vars <- data %>%
  select(where(is.numeric))

# Corrélations (variables numériques seulement; la présence de NA est gérée par use="pairwise")
cor_mat <- cor(num_vars, use = "pairwise.complete.obs")
print(round(cor_mat, 2))

# Paires (peut être un peu lourd; commentez si besoin)
# GGally::ggpairs(num_vars)

# 1.6 Effets potentiels de structure (ville / parc)
data %>%
  ggplot(aes(x = city_id, y = bird_health_index)) +
  geom_boxplot() +
  theme(axis.text.x = element_text(angle = 30, hjust = 1)) +
  ggtitle("bird_health_index selon la ville (city_id)")

data %>%
  ggplot(aes(x = park_id, y = bird_health_index)) +
  geom_boxplot() +
  theme(axis.text.x = element_text(angle = 60, hjust = 1)) +
  ggtitle("bird_health_index selon le parc (park_id)")


# ----------------------------
# MISSION 2 – Modéliser
# Choix méthodo:
# - Random forest de régression (ranger) + CV
# - Imputation des NA via step_impute_bag (robuste, non-paramétrique)
# - Prise en compte de city_id et park_id (facteurs)
# ----------------------------

# 2.1 Split entraînement/test
set.seed(123)
split <- initial_split(data, prop = 0.80)
train_data <- training(split)
test_data  <- testing(split)

# 2.2 Recette de prétraitement
# - Convertir city_id et park_id en facteurs
# - Imputer les numériques manquants (bagging)
# - Créer des indicateurs de "NA" (optionnel mais utile)
# - Encodage one-hot des facteurs
rec <- recipe(bird_health_index ~ city_id + park_id +
                feeder_count + road_density + thrash_can_count +
                shrub_density + raptor_presence,
              data = train_data) %>%
  step_mutate(
    city_id = as.factor(city_id),
    park_id = as.factor(park_id),
    raptor_presence = as.factor(raptor_presence) # présence/absence → facteur (0/1)
  ) %>%
  # indicateurs de NA (peut aider le modèle si NA non aléatoires)
  step_indicate_na(all_predictors()) %>%
  # imputation bagging pour numériques
  step_impute_bag(all_numeric_predictors()) %>%
  # imputation mode pour catégorielles (rare ici)
  step_impute_mode(all_nominal_predictors()) %>%
  # dummies pour facteurs
  step_dummy(all_nominal_predictors(), one_hot = TRUE)

# 2.3 Modèle ranger (RF)
rf_spec <- rand_forest(
  mode  = "regression",
  trees = 1500,
  mtry  = tune(),
  min_n = tune()
) %>%
  set_engine("ranger", importance = "permutation")  # permutation importance côté ranger

# 2.4 Workflow
wf <- workflow() %>%
  add_recipe(rec) %>%
  add_model(rf_spec)

# 2.5 Validation croisée + tuning
set.seed(123)
folds <- vfold_cv(train_data, v = 5)

# grille raisonnable
grid <- grid_regular(
  mtry(range = c(2, 20)),
  min_n(range = c(2, 25)),
  levels = 6
)

set.seed(123)
tuned <- tune_grid(
  wf,
  resamples = folds,
  grid = grid,
  metrics = metric_set(rmse, rsq)
)

# 2.6 Meilleurs hyperparamètres
best_rmse <- select_best(tuned, metric = "rmse")
best_rmse

# 2.7 Finaliser le workflow
final_wf <- finalize_workflow(wf, best_rmse)

# 2.8 Entraîner sur train et évaluer sur test
final_fit <- last_fit(final_wf, split = split, metrics = metric_set(rmse, rsq))

collect_metrics(final_fit)

# Prédictions test + graphique observé vs prédit
test_preds <- collect_predictions(final_fit)

ggplot(test_preds, aes(x = bird_health_index, y = .pred)) +
  geom_point() +
  geom_abline(slope = 1, intercept = 0) +
  ggtitle("Observé vs Prédit (jeu test)") +
  xlab("Observé: bird_health_index") +
  ylab("Prédit")

# ----------------------------
# MISSION 3 – Importance des prédicteurs (version corrigée)
# ----------------------------

# 3.1 Refit final sur toutes les données (pour importance + prédiction finale)
final_model_full <- fit(final_wf, data = data)

# Extraire le modèle entraîné
rf_fit <- final_model_full %>%
  extract_fit_parsnip() %>%
  pluck("fit")

# Importance permutation directement depuis ranger
imp <- ranger::importance(rf_fit)

# Mettre en data.frame
imp_df <- tibble(
  Variable = names(imp),
  Importance = as.numeric(imp)
) %>%
  arrange(desc(Importance))

# Voir les 20 variables les plus importantes
print(head(imp_df, 20))


# ----------------------------
# MISSION 4 – Prédire to_predict.csv (10 individus sans santé)
# - On utilise le même workflow final (imputation incluse)
# - On génère un fichier de sortie
# ----------------------------

# Harmoniser les colonnes attendues (si besoin)
# Ici on suppose: city_id, park_id, feeder_count, road_density, thrash_can_count,
# shrub_density, raptor_presence
# et aucune colonne bird_health_index dans to_pred.

pred_out <- predict(final_model_full, new_data = to_pred) %>%
  bind_cols(to_pred) %>%
  rename(pred_bird_health_index = .pred)

print(pred_out)

# Sauvegarder
write.csv(pred_out, "predictions_to_predict.csv", row.names = FALSE)

message("Fichier écrit: predictions_to_predict.csv")
