#!/usr/bin/env bash
# Скачивает Kubespray (последний стабильный релиз или тег из аргумента)
# и ставит Ansible со всеми зависимостями в виртуальное окружение ansible/.venv
# Запуск:  ./bootstrap-kubespray.sh            (последний релиз)
#          ./bootstrap-kubespray.sh v2.28.0    (конкретный тег)
set -euo pipefail
cd "$(dirname "$0")"

TAG="${1:-}"

[ -d kubespray ] || git clone https://github.com/kubernetes-sigs/kubespray.git kubespray
cd kubespray
git fetch --tags --quiet
if [ -z "$TAG" ]; then
  # последний тег вида vX.Y.Z (без rc/alpha)
  TAG=$(git tag -l 'v2.*' --sort=-v:refname | grep -v -- '-' | head -n1)
fi
echo ">>> Kubespray: $TAG"
git checkout --quiet "$TAG"

cd ..
python3 -m venv .venv
# shellcheck disable=SC1091
source .venv/bin/activate
pip install --upgrade pip
pip install -r kubespray/requirements.txt
echo ">>> Готово. Активация окружения:  source ansible/.venv/bin/activate"
ansible --version | head -n1
