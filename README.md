=====================================================
  DÉPLOIEMENT TERMINÉ
=====================================================

[SUCCESS] Votre application Laravel est maintenant déployée et configurée!
[INFO] Votre application Laravel est accessible à l'adresse:
- HTTP: http://pointage.dubocqsa.fr (redirigé vers HTTPS)
- HTTPS: https://pointage.dubocqsa.fr

[INFO] PgAdmin est accessible à l'adresse: http://pointage.dubocqsa.fr:5050

[INFO] Important: N'oubliez pas de configurer la redirection de port sur votre routeur!
- Le port 80 doit être redirigé vers le port 80 de ce serveur
- Le port 443 doit être redirigé vers le port 443 de ce serveur

[INFO] Pour modifier votre application, vous pouvez:
1. Modifier les fichiers dans le dossier 'www'
2. Reconstruire l'image Docker avec: docker compose build app
3. Redémarrer les conteneurs avec: docker compose restart

[INFO] Pour afficher les logs de votre application, utilisez:
docker compose logs -f app

[INFO] Pour redémarrer tous les services:
docker compose down && docker compose up -d
