### Analyses RIVE HACKING 2026
### Équipe 8SAE

  #0. R environnement
library(tidyverse)
library(mlr3verse)
library(mlr3viz)
library(car)
library(performance)
library(lme4)
library(lmerTest)
library(mgcv)
library(mgcViz)

set.seed(123)
#---------------------------------------
  #1. Explorer ####
df = read.csv("dataset.csv")

  ##1.1 explorations des types de variables, NAs et distribution des groupes
summary(df) # voir les types de variable et leurs range de valeur

length(unique(df$park_id)) # nb de niveaux de park_id
length(unique(df$city_id)) # nb de niveaux de city_id

# Nb de NA dans la base de données par ville
df %>% 
  group_by(city_id) %>% 
  summarize(across(everything(), ~sum(is.na(.))),
            ntot = n())

# Nb d'observations dans la base de données sans NA
df %>% 
  drop_na() %>% 
  group_by(city_id) %>%  # par ville seulement
  summarize(across(everything(), ~sum(is.na(.))),
            ntot = n())

df %>% 
  drop_na() %>% 
  group_by(city_id, park_id) %>% # par ville et parc
  summarize(across(everything(), ~sum(is.na(.))),
            ntot = n())

#Nb observations sans NA
df %>% 
  drop_na() %>% 
  group_by(city_id, park_id) %>% 
  summarize(n=n())

##1.2. explorer les distributions des variables

# globalement
chart.Correlation(df %>% select(-city_id, -park_id) %>% 
                    mutate(feeder_count = as.numeric(feeder_count),
                           thrash_can_count = as.numeric(thrash_can_count),
                           raptor_presence = as.numeric(raptor_presence)),
                  histogram=TRUE, pch=21)
# par ville
for(i in unique(df$city_id)){
  df2 = df %>% filter(city_id == i)
  pi = chart.Correlation(df2 %>% 
                           select(-city_id, -park_id) %>% 
                           mutate(feeder_count = as.numeric(feeder_count),
                                  thrash_can_count = as.numeric(thrash_can_count),
                                  raptor_presence = as.numeric(raptor_presence)),
                         histogram=TRUE, pch=19, main=i)
  
  print(pi)
}

# visualisation alternative via mlr3
task = as_task_regr(df %>% drop_na(), target="bird_health_index")
autoplot(task, type="pairs")

#---------------------------------------------
  #2. Modéliser ####

##2.1. modèles classiques ####
###2.1.1. Modèle linéaire simple (lm) ####
df.lm <- lm(bird_health_index ~feeder_count + road_density + thrash_can_count 
            + shrub_density + raptor_presence, data = df)
vif(df.lm) # pour vérifier l'autocorrelation
summary(df.lm) # pour vérifier le modèle

# modèle sans thrash_can_count
df.lm2<- lm(bird_health_index ~feeder_count + road_density + 
              shrub_density + raptor_presence , data = df %>% drop_na())
vif(df.lm2) # pour vérifier l'autocorrelation
summary(df.lm2) # pour vérifier le modèle

###2.1.2. Modèle linéaire mixte (mlm/lmer) ##
# ajout d'effet aléatoire imbriqué
df.mlm <- lmer(bird_health_index ~ feeder_count + road_density + thrash_can_count 
               + shrub_density + raptor_presence + (1|city_id/park_id), data = df)
vif(df.mlm) # pour vérifier l'autocorrelation
summary(df.mlm) # pour vérifier le modèle

# pour inspecter les pvalues des prédicteurs
lmerTest::as_lmerModLmerTest(df.mlm) %>% 
  summary()

# modèle sans thrash_can_count
df.mlm2 <- lmer(bird_health_index ~ feeder_count + road_density  
                + shrub_density + raptor_presence + (1|city_id/park_id), data = df)

summary(df.mlm2) # pour vérifier le modèle

###2.1.3. Modèles additifs généralisés (GAM) ##
# ajout d'effets aléatoires bs="re" et de splines non linéaire s()
df.gam <- gam(bird_health_index ~ s(feeder_count) + s(road_density) + s(thrash_can_count) + 
                s(shrub_density) + raptor_presence + s(city_id, bs = "re") + s(park_id, bs = "re"), 
              data = df %>% drop_na() %>% mutate(city_id = as.factor(city_id),
                                                 park_id = as.factor(park_id)), method = "REML")
summary(df.gam) # pour vérifier le modèle
gam.check(df.gam) # pour vérifier les EDF (près de 1 = linéaire)

# modèle sans trash_can_count et avec les splines linéaires retirés
df.gam2 <- gam(bird_health_index ~ s(feeder_count) + road_density +  
                 s(shrub_density) + raptor_presence + s(city_id, bs = "re") + s(park_id, bs = "re"), 
               data = df %>% drop_na() %>% mutate(city_id = as.factor(city_id),
                                                  park_id = as.factor(park_id)), method = "REML")
gam.check(df.gam2) # validation du modèle
summary(df.gam2) # pour vérifier le modèle

#Comparaison performance des modèles
compare_performance(df.lm, df.lm2, df.mlm, df.mlm2, df.gam, df.gam2)

#Visualiser les GAM
m2<- getViz(df.gam2)
plot(m2, allTerms = T) # appuyer sur enter dans la console


##2.2. Machine Learning ##
# utiliser Caret pour générer un modèle optimisé avec ranger
df2 = df %>% drop_na() %>% mutate(city_id = as.factor(city_id), park_id = as.factor(park_id)) %>% 
  mutate(context_id = as.factor(paste0(city_id,"-",park_id))) # préparation de la base de données et d'une colonne unique pour les facteurs

folds = createFolds(df2$context_id, k=5,list=T) # pour créer les replis de validation basés sur city_id et park_id

# entrainement du modèle
rangerm = train(
  bird_health_index ~., data=df2 %>% select(-context_id,-city_id,-park_id),
  method = "ranger",
  tuneLength = 3, # essayer 3 valeurs par paramètre clé
  trControl = trainControl(method="cv", #crossvalidation
                           index=folds,
                           verboseIter = T),
  num.trees = 1000,
  importance = "permutation")

plot(rangerm) # visualisation de la calibration
rangerm # survol de la calibration
rangerm$finalModel # survol du modèle sélectionné; MSE OOB 141.73, R2 OOB 0.35

#----------------------------------------------------
  #3. Id. prédicteurs importants ####
barplot(sort(importance(rangerm$finalModel),decreasing = T),las=2) # graphique des prédicteurs importants

#---------------------------------------------------
  #4. Prédire ####

#4.1 Prédictions modèle classique
pred_df <- read.csv("to_predict.csv")
pred_df <-pred_df %>%  mutate(bird_health_index = predict(df.gam2, pred_df))

#4.2 Prédictions machine learning
pred_df2 = read.csv("to_predict.csv")
pred_df2$bird_health_index = predict(rangerm,pred_df2)

#---------------------------------------------------
  #5. Décrire et illustrer ####

df2 = rbind(df %>% drop_na() %>% mutate(pred = predict(df.gam2,.),
                                        id = "gam"),
            df %>% drop_na() %>% mutate(pred = predict(rangerm,.),
                                        id = "ranger"))

df2 %>% ggplot(aes(x=bird_health_index,y=pred, col=id))+
  geom_point()+
  geom_smooth(se=T)+
  facet_wrap(~id)
