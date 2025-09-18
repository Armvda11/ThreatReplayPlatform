#!/usr/bin/env bash
set -euo pipefail

# ThreatReplayPlatform helper
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="${ROOT}/infra/docker-compose.yml"
DOCKER=(docker compose -f "${COMPOSE_FILE}")

PCAP_DIR="${ROOT}/data/pcaps"
LOG_DIR="${ROOT}/infra/logs/suricata"
EVE_FILE="${LOG_DIR}/eve.json"

bold(){ printf "\033[1m%s\033[0m\n" "$*"; }
info(){ printf "➜ %s\n" "$*"; }
err(){ printf "\033[31m✗ %s\033[0m\n" "$*" >&2; }

need_dirs() {
  mkdir -p "${PCAP_DIR}" "${LOG_DIR}"
}

has_service() {
  "${DOCKER[@]}" config --services 2>/dev/null | grep -qx "$1"
}

open_kibana() {
  local url="http://localhost:5601"
  if command -v wslview >/dev/null 2>&1; then wslview "$url" || true
  elif command -v xdg-open >/dev/null 2>&1; then xdg-open "$url" || true
  fi
  info "Kibana: ${url}"
}

usage() {
cat <<'USAGE'
Usage: ./trp.sh <commande> [options]

Commandes principales:
  up                   Démarre la stack (ES, Kibana, Filebeat, Suricata, ElastAlert si présent)
  down                 Stoppe et supprime les conteneurs (pas les volumes)
  restart [svc|all]    Redémarre un service (elasticsearch|kibana|filebeat|suricata|elastalert) ou tout
  status               Affiche l’état des conteneurs + indices Elasticsearch
  logs <svc>           Suit les logs d’un service (suricata|filebeat|kibana|elasticsearch|elastalert)
  pcap <fichier>       Définit le PCAP actif (copie vers data/pcaps/attack.pcap) et rejoue
  tail-eve             Affiche les dernières lignes de infra/logs/suricata/eve.json
  reset-eve            Réinitialise eve.json (crée .OLD), rejoue Suricata
  reset-filebeat       Efface le registry de Filebeat (force la réingestion), puis restart
  kibana               Ouvre Kibana dans le navigateur (si possible)

Exemples:
  ./trp.sh up
  ./trp.sh pcap nmap_scan.pcap
  ./trp.sh logs suricata
  ./trp.sh status
  ./trp.sh reset-filebeat
USAGE
}

cmd_up() {
  need_dirs
  bold "Démarrage des services…"
  "${DOCKER[@]}" up -d elasticsearch kibana filebeat suricata || true
  if has_service elastalert; then
    "${DOCKER[@]}" up -d elastalert || true
  fi
  open_kibana
}

cmd_down() {
  bold "Arrêt de la stack…"
  "${DOCKER[@]}" down
}

cmd_restart() {
  local svc="${1:-all}"
  if [[ "$svc" == "all" ]]; then
    bold "Redémarrage de tous les services…"
    "${DOCKER[@]}" down
    cmd_up
  else
    bold "Redémarrage de ${svc}…"
    "${DOCKER[@]}" restart "${svc}"
  fi
}

cmd_status() {
  bold "Containers:"
  "${DOCKER[@]}" ps
  bold "Indices Elasticsearch:"
  if command -v curl >/dev/null 2>&1; then
    curl -s 'http://localhost:9200/_cat/indices?v' | sed -n '1,200p' || true
  else
    info "curl non disponible pour afficher les indices."
  fi
  open_kibana
}

cmd_logs() {
  local svc="${1:-}"
  [[ -z "$svc" ]] && { err "Précise un service (suricata|filebeat|kibana|elasticsearch|elastalert)"; exit 1; }
  bold "Logs ${svc} (Ctrl-C pour quitter)…"
  "${DOCKER[@]}" logs -f "${svc}"
}

cmd_pcap() {
  local file="${1:-}"
  [[ -z "$file" ]] && { err "Précise le nom du pcap dans data/pcaps (ex: nmap_scan.pcap)"; exit 1; }
  local src="${PCAP_DIR}/${file}"
  [[ ! -f "$src" ]] && { err "Fichier introuvable: ${src}"; exit 1; }

  need_dirs
  cp -f "$src" "${PCAP_DIR}/attack.pcap"
  info "PCAP actif -> ${PCAP_DIR}/attack.pcap"
  # on remet à zéro eve pour bien voir la nouvelle lecture
  : > "${EVE_FILE}" || true

  bold "Rejeu du PCAP avec Suricata…"
  "${DOCKER[@]}" rm -sf suricata >/dev/null 2>&1 || true
  "${DOCKER[@]}" up -d suricata
  sleep 2
  info "Suricata a relu attack.pcap. Redémarrage Filebeat pour pousser l'indexation…"
  "${DOCKER[@]}" restart filebeat
  info "Astuce Kibana: passe la période sur 'All time' et clique Refresh."
}

cmd_tail_eve() {
  [[ -f "${EVE_FILE}" ]] || { err "eve.json introuvable: ${EVE_FILE}"; exit 1; }
  bold "Dernières lignes de eve.json (Ctrl-C pour quitter)…"
  tail -f "${EVE_FILE}"
}

cmd_reset_eve() {
  need_dirs
  if [[ -f "${EVE_FILE}" ]]; then
    mv "${EVE_FILE}" "${EVE_FILE}.$(date +%Y%m%d%H%M%S).OLD"
    info "Ancien eve.json sauvegardé."
  fi
  : > "${EVE_FILE}"
  info "eve.json réinitialisé."
  bold "Rejeu Suricata…"
  "${DOCKER[@]}" rm -sf suricata >/dev/null 2>&1 || true
  "${DOCKER[@]}" up -d suricata
  sleep 2
  "${DOCKER[@]}" restart filebeat
}

cmd_reset_filebeat() {
  bold "Nettoyage du registry Filebeat (force la réingestion)…"
  # nécessite un container filebeat en cours d’exécution
  "${DOCKER[@]}" up -d filebeat
  "${DOCKER[@]}" exec -T filebeat rm -rf /usr/share/filebeat/data/registry || true
  "${DOCKER[@]}" restart filebeat
  info "Fait. Si besoin, actualise Kibana (All time + Refresh)."
}

cmd_kibana() {
  open_kibana
}

main() {
  local cmd="${1:-help}"; shift || true
  case "$cmd" in
    up) cmd_up "$@";;
    down) cmd_down;;
    restart) cmd_restart "${1:-all}";;
    status) cmd_status;;
    logs) cmd_logs "${1:-}";;
    pcap) cmd_pcap "${1:-}";;
    tail-eve) cmd_tail_eve;;
    reset-eve) cmd_reset_eve;;
    reset-filebeat) cmd_reset_filebeat;;
    kibana) cmd_kibana;;
    help|-h|--help) usage;;
    *) err "Commande inconnue: $cmd"; usage; exit 1;;
  esac
}
main "$@"
