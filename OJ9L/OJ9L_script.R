# ============================================================
# ANALYSE DE LA SANTÉ D’OISEAUX URBAINS
# SCRIPT R COMMENTÉ ET EXÉCUTABLE
# ============================================================


# ------------------------------------------------------------
# 0. Packages
# ------------------------------------------------------------
# tidyverse : manipulation et visualisation des données
# lme4      : modèles linéaires mixtes
# lmerTest  : p-values pour les modèles mixtes
# car       : diagnostics (VIF)


library(lme4)
library(lmerTest)
library(ggplot2)
library(readxl)
library(tidyverse)
library(forcats)
library(tidyr)
library(dplyr)
library(ggpubr)
library(car)
library(performance)
library(see)
library(lubridate)
library(patchwork)
library(itsadug)
library(mgcv)

# ------------------------------------------------------------
# 1. Importation des données
# ------------------------------------------------------------
# dataset : individus avec bird_health_index mesuré
# to_pred : individus sans bird_health_index (à prédire)

dataset <- read.csv("dataset.csv")
to_pred <- read.csv("to_predict.csv")

# Vérification rapide de la structure
str(dataset)
summary(dataset)


# ------------------------------------------------------------
# 2. Préparation des données
# ------------------------------------------------------------

# ------------------
# 2.1 Variables catégorielles
# ------------------
# city_id et park_id représentent la structure spatiale

dataset$city_id <- factor(dataset$city_id)
dataset$park_id <- factor(dataset$park_id)

to_pred$city_id <- factor(to_pred$city_id)
to_pred$park_id <- factor(to_pred$park_id)


# ------------------
# 2.2 Standardisation des variables continues
# ------------------
# Objectifs :
# - rendre les coefficients comparables
# - améliorer la convergence du modèle
# - éviter qu'une variable domine par son unité

vars_cont <- c("feeder_count",
               "road_density",
               "thrash_can_count",
               "shrub_density")

# Calcul des paramètres de standardisation
# UNIQUEMENT à partir du jeu de données d'entraînement
scale_center <- sapply(dataset[vars_cont], mean, na.rm = TRUE)
scale_scale  <- sapply(dataset[vars_cont], sd,   na.rm = TRUE)

# Application aux deux jeux de données
dataset[vars_cont] <- scale(dataset[vars_cont],
                            center = scale_center,
                            scale  = scale_scale)

to_pred[vars_cont] <- scale(to_pred[vars_cont],
                            center = scale_center,
                            scale  = scale_scale)


# ------------------------------------------------------------
# 3. Exploration rapide
# ------------------------------------------------------------

# ------------------
# 3.1 Corrélations entre variables continues - sans les NAs
# ------------------

cor(dataset[, vars_cont], use = "complete.obs")


# ------------------
# 3.2 Colinéarité (Variance Inflation Factor)
# ------------------
# VIF > 5 indique un problème potentiel

vif(lm(bird_health_index ~ feeder_count +
         road_density +
         thrash_can_count +
         shrub_density +
         raptor_presence,
       data = dataset))


# ------------------------------------------------------------
# 4. Modèle global (écologiquement complet)
# ------------------------------------------------------------
# Effets fixes  : variables environnementales
# Effets aléatoires : parc imbriqué dans la ville

dataset_complete <- na.omit(dataset[, c("bird_health_index", "feeder_count", 
                                        "road_density", "shrub_density", 
                                        "thrash_can_count", "raptor_presence", 
                                        "city_id", "park_id")])
model_full <- lmer(bird_health_index ~ feeder_count + road_density + thrash_can_count + 
                     shrub_density + raptor_presence + (1 | city_id / park_id),
                   data = dataset_complete, REML = FALSE)




# Résumé du modèle global
summary(model_full)


# ------------------------------------------------------------
# 5. Sélection du modèle final (approche raisonnée)
# ------------------------------------------------------------
# On compare des modèles biologiquement plausibles
# à l'aide du critère AIC

model_reduced <- lmer(bird_health_index ~ feeder_count + road_density + shrub_density + 
                        (1 | city_id / park_id),
                      data = dataset_complete, REML = FALSE)

# Comparaison des modèles
AIC(model_full, model_reduced)

# Choix du modèle final
model_final <- model_full

summary(model_final)

check_model(model_final)

a <- check_model(model_final, panel = FALSE)

plot(a)
# ------------------------------------------------------------
# 6. Importance des variables
# ------------------------------------------------------------
# Les variables étant standardisées,
# les coefficients sont directement comparables

summary(model_final)$coefficients


# ------------------------------------------------------------
# 7. Diagnostics du modèle
# ------------------------------------------------------------

par(mfrow = c(1, 2))

# Résidus vs valeurs ajustées
plot(fitted(model_final), resid(model_final),
     xlab = "Valeurs ajustées",
     ylab = "Résidus")
abline(h = 0, lty = 2)

# Normalité des résidus
qqnorm(resid(model_final))
qqline(resid(model_final))

par(mfrow = c(1, 1))


# ------------------------------------------------------------
# 8. Prédiction des 10 individus
# ------------------------------------------------------------
# allow.new.levels = TRUE permet de prédire
# pour de nouveaux parcs ou villes

pred_health <- predict(
  model_final,
  newdata = to_pred,
  allow.new.levels = TRUE
)

to_pred$predicted_bird_health_index <- pred_health


# ------------------------------------------------------------
# 9. Résultats finaux
# ------------------------------------------------------------

to_pred %>%
  select(city_id, park_id, predicted_bird_health_index)

# Sauvegarde des prédictions
write.csv(to_pred,
          "predicted_bird_health.csv",
          row.names = FALSE)


# ============================================================
# FIN DU SCRIPT
# ============================================================
