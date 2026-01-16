# Rapport d'Évaluation - Équipe QRJG - Solution 5

## 1. Résumé de l'Évaluation

L'équipe QRJG propose une seconde solution utilisant le framework {tidymodels} avec Random Forest ({ranger}) et une approche moderne de prétraitement. Le script est particulièrement bien structuré avec des sections correspondant aux quatre missions de l'exercice. L'utilisation de tuning des hyperparamètres par validation croisée et d'imputation automatique des valeurs manquantes démontre une approche méthodologique robuste.

---

## 2. Tableau des Scores (Critères C1-C5)

| Critère | Score | Description |
|---------|-------|-------------|
| **C1** - Analyse techniquement correcte et choix justifiés | 4 | Excellente pipeline de prétraitement avec imputation, standardisation et encodage. Tuning des hyperparamètres (mtry, min_n) par grille. |
| **C2** - Code reproductible et lisible | 5 | Utilisation de {tidymodels} qui garantit une syntaxe cohérente. `set.seed(123)` pour la reproductibilité. Sauvegarde des prédictions en CSV. |
| **C3** - Transparence sur les incertitudes et limitations | 3 | Les métriques RMSE et R² sont calculées sur le jeu de test. Visualisation observé vs prédit. Toutefois, pas de discussion des limitations. |
| **C4** - Interprétations et conclusions claires et supportées | 4 | L'importance des variables est calculée et les 20 plus importantes sont affichées. Graphique observé vs prédit fourni. |
| **C5** - Analyse à la fine pointe de la technologie | 5 | {tidymodels} est le framework moderne de référence pour le ML en R. Imputation par bagging, indicateurs de NA, one-hot encoding automatique. |

**Score moyen pondéré** : 4.2/5

---

## 3. Commentaires Détaillés sur la Rigueur Scientifique

### Points Positifs

1. **Framework moderne et robuste** : L'utilisation de {tidymodels} assure une pipeline de modélisation cohérente, reproductible et maintenable. Cette approche suit les meilleures pratiques actuelles du ML en R (Kuhn & Silge, 2022).

2. **Exploration approfondie des données** : L'utilisation de {skimr} et {naniar} pour l'exploration est exemplaire :
   - Taux de NA par variable
   - Visualisation du pattern de données manquantes
   - Distribution de la variable réponse
   - Analyse des corrélations

3. **Gestion sophistiquée des valeurs manquantes** : La recette de prétraitement inclut :
   - `step_indicate_na()` : crée des indicateurs binaires pour les valeurs manquantes (utile si le mécanisme de NA est informatif)
   - `step_impute_bag()` : imputation par bagging pour les variables numériques
   - `step_impute_mode()` : imputation par mode pour les catégorielles

4. **Tuning par grille avec validation croisée** : L'optimisation de `mtry` et `min_n` sur une grille de 36 combinaisons (6×6) avec 5-fold CV est une approche standard et robuste.

5. **Évaluation sur données indépendantes** : L'utilisation de `last_fit()` pour évaluer le modèle final sur le jeu de test est la bonne pratique recommandée par {tidymodels}.

### Points à Améliorer

1. **Structure hiérarchique ignorée** : Contrairement à la Solution 4 (MERF), cette solution ne prend pas en compte explicitement la structure parc/ville. Bien que city_id et park_id soient inclus comme prédicteurs (après one-hot encoding), l'autocorrélation intra-groupe n'est pas modélisée.

2. **Validation croisée non stratifiée par groupe** : Les folds de validation croisée sont créés sans tenir compte de la structure hiérarchique, ce qui peut mener à une surestimation de la performance (fuite de données entre groupes similaires).

3. **Nombre d'arbres fixé** : `trees = 1500` est fixé sans justification ni tuning. Bien que ce soit généralement suffisant, une vérification de la stabilisation de l'erreur OOB serait bénéfique.

4. **Interprétation écologique limitée** : Le script affiche les 20 variables les plus importantes mais n'interprète pas leur signification biologique.

### Considérations sur l'Imputation

L'imputation par bagging (`step_impute_bag()`) est un choix judicieux car :
- Elle est non-paramétrique
- Elle capture les relations non-linéaires entre variables
- Elle est robuste aux outliers

Cependant, l'absence de discussion sur le mécanisme des données manquantes (MCAR, MAR, MNAR) est une lacune.

---

## 4. Analyse Technique du Code R

### Points Forts

1. **Pipeline tidymodels complète** : La séquence recipe → model spec → workflow → tune → finalize → last_fit est exemplaire.

2. **Recette de prétraitement robuste** :

```r
rec <- recipe(bird_health_index ~ city_id + park_id + 
                feeder_count + road_density + thrash_can_count +
                shrub_density + raptor_presence,
              data = train_data) %>%
  step_mutate(...) %>%
  step_indicate_na(all_predictors()) %>%
  step_impute_bag(all_numeric_predictors()) %>%
  step_impute_mode(all_nominal_predictors()) %>%
  step_dummy(all_nominal_predictors(), one_hot = TRUE)
```

3. **Importance des variables via ranger** : L'extraction de l'importance de permutation directement depuis l'objet ranger est correcte.

4. **Harmonisation des noms de colonnes** : La vérification et le renommage potentiel de `Bird_health_index` → `bird_health_index` est une bonne pratique défensive.

### Points Faibles

1. **Grille potentiellement trop large pour mtry** : `mtry(range = c(2, 20))` avec `levels = 6` peut inclure des valeurs de mtry > nombre de prédicteurs après one-hot encoding, ce qui est sous-optimal.

2. **Visualisation ggpairs commentée** : Le code `# GGally::ggpairs(num_vars)` est commenté avec le note "peut être un peu lourd", suggérant une exécution abandonnée.

3. **Sauvegarde locale non portable** : `write.csv(..., row.names = FALSE)` sauvegarde dans le répertoire de travail sans chemin explicite.

### Comparaison avec Solution 4

| Aspect | Solution 4 (MERF) | Solution 5 (tidymodels) |
|--------|-------------------|------------------------|
| Structure hiérarchique | ✓ Modélisée via effets aléatoires | ✗ Ignorée (sauf one-hot) |
| Gestion des NA | drop_na() | ✓ Imputation bagging |
| Tuning | Paramètres fixes | ✓ Grille CV |
| Framework | LongituRF | tidymodels |
| Reproductibilité | Bonne | Excellente |

---

## 5. Références Citées

- Kuhn, M., & Silge, J. (2022). *Tidy Modeling with R*. O'Reilly Media.
- Breiman, L. (2001). Random Forests. *Machine Learning*, 45(1), 5-32.
- Little, R. J. A., & Rubin, D. B. (2019). *Statistical Analysis with Missing Data* (3rd ed.). Wiley.
- Wright, M. N., & Ziegler, A. (2017). ranger: A Fast Implementation of Random Forests. *Journal of Statistical Software*, 77(1), 1-17.

---

## Note Finale

**Note globale : 8/10**

Cette solution démontre une excellente maîtrise du framework {tidymodels} et des meilleures pratiques de machine learning en R. L'approche de prétraitement est particulièrement robuste. La principale faiblesse est l'absence de prise en compte de la structure hiérarchique des données.

---

## Détection IA

**Score : 1**

Le script présente toutes les caractéristiques d'une génération assistée par IA : structure parfaitement organisée en "missions", commentaires exhaustifs et pédagogiques, utilisation systématique des meilleures pratiques tidymodels sans erreur. Le style est trop uniforme et complet pour un travail humain typique sous contrainte de temps.
