# Ansible + Kubespray: установка Kubernetes на ВМ

Файлы:
- `inventory/hosts.ini` — создаётся Terraform автоматически
- `inventory/group_vars/k8s_cluster/api-cert.yml` — тоже от Terraform (IP для сертификата API)
- `inventory/group_vars/k8s_cluster/overrides.yml`, `addons.yml` — наши настройки Kubespray
- `prepare.yml` — подготовка нод
- `bootstrap-kubespray.sh` — скачивает Kubespray и ставит Ansible в venv

## Один раз (WSL2)
```
sudo apt update && sudo apt install -y git python3-venv python3-pip
cd ansible
./bootstrap-kubespray.sh
```

## Установка кластера (после `terraform apply`)
```
cd ansible
source .venv/bin/activate
export ANSIBLE_HOST_KEY_CHECKING=False

ansible -i inventory/hosts.ini all -m ping          # все ноды должны ответить pong
ansible-playbook -i inventory/hosts.ini prepare.yml

cd kubespray
ansible-playbook -i ../inventory/hosts.ini --become cluster.yml    # 20-40 минут
```

## kubeconfig
Kubespray кладёт файл в `ansible/inventory/artifacts/admin.conf`.
```
mkdir -p ~/.kube
cp inventory/artifacts/admin.conf ~/.kube/config
sed -i "s#server: .*#server: https://<IP_CONTROL_PLANE>:6443#" ~/.kube/config
kubectl get nodes
```
IP берём из `terraform output`.
