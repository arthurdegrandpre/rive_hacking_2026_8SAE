#Packages
library(tidyverse)
library(ggplot2)
library(LongituRF)
library(randomForest)
library(rsample)
library(mice)

rm(list=ls())

######## Évaluation préalable des variables ##########

# Ouvrir le jeu de données
data <- read.csv("dataset.csv", header = TRUE)

# Description des variables
stats <- data %>%
  select(tail(names(data), 6)) %>%   # sélectionne les 6 dernières colonnes
  summarise(across(
    everything(),
    list(mean = ~mean(.x, na.rm = TRUE),
         sd   = ~sd(.x, na.rm = TRUE))
  ))

stats

# Visualisation des variables
data_long <- data %>%
  select(tail(names(data), 6)) %>%
  pivot_longer(cols = everything(),
               names_to = "variable",
               values_to = "value")

ggplot(data_long, aes(x = value)) +
  geom_histogram(aes(y = after_stat(density)), bins = 30, fill = "grey80", color = "black") +
  geom_density(linewidth = 1) +
  facet_wrap(~ variable, scales = "free") +
  theme_minimal() +
  labs(x = "Valeur", y = "Densité",
       title = "Distribution des six dernières variables")

######## Modélisation par Random Forest ##########

# --- 1) Préparer les données ---
fixed_vars <- c("feeder_count", "raptor_presence", "road_density",
                "shrub_density", "thrash_can_count")

df <- data %>%
  select(bird_health_index, all_of(fixed_vars), city_id, park_id) %>%
  mutate(
    city_id = factor(city_id),
    park_id = factor(park_id),
    # Regroupement "parc dans ville" (approx. pour 2 effets aléatoires)
    id_merf = interaction(city_id, park_id, drop = TRUE)
  ) %>% tidyr::drop_na()

#Imputation des valeurs manquantes
#imp <- mice(df, m = 5, method = "cart", seed = 123)
#df <- complete(imp, 1)


# MERF (LongituRF) attend: X (matrix), Y (vector), id (vector), Z (matrix), time (vector), sto
X <- as.matrix(df[, fixed_vars])
Y <- df$bird_health_index
id <- df$id_merf

# Random effects design matrix Z:
# - random intercept seulement => colonne de 1
Z <- matrix(1, nrow = nrow(df), ncol = 1)
time <- rep(1, nrow(df))

# --- 2) Split train/test --- 80-20
set.seed(123)
split <- initial_split(df, prop = 0.80)
train <- training(split)
test  <- testing(split)

X_train <- as.matrix(train[, fixed_vars])
Y_train <- train$bird_health_index
id_train <- train$id_merf
Z_train <- matrix(1, nrow = nrow(train), ncol = 1)
time_train <- rep(1, nrow(train))

X_test <- as.matrix(test[, fixed_vars])
Y_test <- test$bird_health_index
id_test <- test$id_merf
Z_test <- matrix(1, nrow = nrow(test), ncol = 1)
time_test <- rep(1, nrow(test))

# --- 3) Fit MERF ---
set.seed(123)
merf_fit <- MERF(
  X = X_train,
  Y = Y_train,
  id = id_train,
  Z = Z_train,
  iter = 100,
  mtry = ceiling(ncol(X_train)/3),
  ntree = 500,
  time = time_train,
  sto = "none",      # pas de processus stochastique longitudinal
  delta = 0.001
)

# --- 4) Prédire ---
pred_test <- predict(merf_fit, X = X_test, Z = Z_test, id = id_test, time = time_test)

# --- 5) Évaluer ---
rmse <- sqrt(mean((pred_test - Y_test)^2))
r2   <- 1 - sum((pred_test - Y_test)^2) / sum((Y_test - mean(Y_test))^2)

rmse # root-mean-square-error
r2 # r2 validation croisée

######## Importance relative des variable ##########

imp_sd <- merf_fit$forest$importanceSD

if (is.matrix(imp_sd) || is.data.frame(imp_sd)) {
  imp_sd <- imp_sd[, 1]
}

imp_df <- data.frame(
  variable = names(imp_sd),
  importance = as.numeric(imp_sd)
) |>
  dplyr::arrange(dplyr::desc(importance)) |>
  dplyr::mutate(importance_rel = importance / sum(importance))

imp_df # Tableau des importances relatives

# Visualisation des importances relatives

ggplot(imp_df, aes(x = reorder(variable, importance_rel), y = importance_rel)) +
  geom_col() +
  coord_flip() +
  theme_minimal() +
  labs(x = "Variable", y = "Importance relative (somme = 1)",
       title = "Importance relative des prédicteurs (MERF)")

######## Prédiction des 10 individus manquants ##########

# 1) Charger le fichier à prédire
newdata <- read.csv("to_predict.csv")

fixed_vars <- c("feeder_count", "raptor_presence",
                "road_density", "shrub_density", "thrash_can_count")

# 2) Construire id_test exactement comme à l'entraînement
newdata <- newdata %>%
  mutate(
    city_id = factor(city_id),
    park_id = factor(park_id),
    id_test = interaction(city_id, park_id, drop = TRUE)   # ou ton id exact si différent
  )

# 3) Construire X et Z à partir de newdata (IMPORTANT)
X_new <- as.matrix(newdata[, fixed_vars])
id_new_chr <- as.character(newdata$id_test)

n <- nrow(newdata)

# Random intercept => Z doit être n x 1
Z_new <- matrix(1, nrow = n, ncol = 1)
time_new <- rep(1, n)

# --- Fixed part (RF) ---
rf_pred <- as.numeric(predict(merf_fit$forest, newdata = as.data.frame(X_new)))

# --- Random effects ---
id_train_chr <- as.character(merf_fit$id_btilde)
b_hat <- merf_fit$random_effects

# Cas intercept seul
if (is.null(dim(b_hat))) {
  
  re_map <- setNames(as.numeric(b_hat), id_train_chr)
  re_new <- re_map[id_new_chr]
  re_new[is.na(re_new)] <- 0
  
  pred_Y <- rf_pred + as.numeric(re_new)
  
} else {
  
  b_hat <- as.matrix(b_hat)
  q <- ncol(b_hat)
  
  # rownames pour correspondance des ids
  if (is.null(rownames(b_hat))) rownames(b_hat) <- id_train_chr
  
  # B_new : n x q
  B_new <- matrix(0, nrow = n, ncol = q)
  idx <- match(id_new_chr, rownames(b_hat))
  ok <- !is.na(idx)
  B_new[ok, ] <- b_hat[idx[ok], , drop = FALSE]
  
  # Z_new doit être n x q (si q>1 on complète par 0)
  if (ncol(Z_new) != q) {
    Z_fix <- matrix(0, nrow = n, ncol = q)
    Z_fix[, 1] <- 1
    Z_new <- Z_fix
  }
  
  re_part <- rowSums(Z_new * B_new)
  pred_Y <- rf_pred + re_part
}

pred_Y # Valuers prédites des 10 individus


######## Additionnel: Relation bird_health_index observé vs. prédit ##########

fixed_vars <- c("feeder_count", "raptor_presence",
                "road_density", "shrub_density", "thrash_can_count")

# Construire X, id, Z à partir de df (mêmes objets qu'à l'entraînement)
X_all  <- as.matrix(df[, fixed_vars])
id_all <- as.character(df$id_merf)
n <- nrow(df)

Z_all    <- matrix(1, nrow = n, ncol = 1)
time_all <- rep(1, n)

# Prédictions MERF
pred_all <- predict(merf_fit,
                    X = X_all,
                    Z = Z_all,
                    id = id_all,
                    time = time_all)


plot_df <- data.frame(
  observed  = df$bird_health_index,
  predicted = as.numeric(pred_all)
)

ggplot(plot_df, aes(x = observed, y = predicted)) +
  geom_point(alpha = 0.6) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed") +
  theme_minimal() +
  labs(
    x = "bird_health_index observé",
    y = "bird_health_index prédit",
    title = "MERF – Prédit vs Observé (jeu d'entraînement)"
  )

r2_pred_obs <- (cor(plot_df$observed,plot_df$predicted))^2

r2_pred_obs
