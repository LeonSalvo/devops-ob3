# DevOps OB3

Este proyecto usa un script `init.sh` que hace:
 - analiza la imagen
 - instala herramientas de seguridad
 - despliega la app en Kubernetes y genera los reportes

Todo se ejecuta en un namespace llamado **devops-ucu**.

---

## Qué hace el script

### 1. Revisar requisitos
Verifica que tengas instalados:
- Node y npm  
- Docker  
- kubectl  
- Helm  
- kube-linter  
- Trivy

---

### 2. Instalar dependencias y analizar el código
- Corre **npm install**  
- Genera un informe de **npm audit** en `reports/npm-audit.txt`  
- Ejecuta **ESLint** sobre el código del backend

---

### 3. Analizar la imagen Docker
- Hace un pull de la imagen si no está en local  
- Corre **Trivy** y guarda el reporte en `reports/trivy-report.txt`  
- Analiza el tamaño, capas y buenas prácticas  
  - Guarda todo en `reports/image-analysis.md`

---

### 4. Instalar Kyverno y aplicar políticas
Instala Kyverno en el namespace **kyverno**, espera las CRDs y aplica las políticas de `k8s/policies`.  
También prueba un manifiesto **NO conforme** y guarda el resultado en `reports/kyverno-noncompliant.log`.

---

### 5. Ejecutar Kube-linter
Analiza todos los manifiestos del proyecto y guarda el resultado en:

```
reports/kubelinter.txt
```

---

### 6. Desplegar la app en Kubernetes
- Crea el namespace `devops-ucu`  
- Instala el release Helm `backend`  
- Espera a que el deployment quede listo  

---

### 7. Exponer la API en localhost
Hace un port-forward:

```
localhost:3000 → backend-svc:80
```

La API queda accesible en:  
`http://localhost:3000`

---

### 8. Limpieza
Cuando tocás ENTER:
- corta port-forward  
- desinstala el release  
- borra el pod no conforme  

Kyverno queda instalado.

---

## Reportes generados

Carpeta `reports/`:

- npm-audit.txt  
- trivy-report.txt  
- image-analysis.md  
- kyverno-noncompliant.log  
- kubelinter.txt  

---

## Cómo ejecutar

Dar permisos una vez:

```bash
chmod +x init.sh
```

Ejecutar:

```bash
./init.sh
```