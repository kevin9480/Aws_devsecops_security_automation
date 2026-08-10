# AWS Secure Lifecycle Service

DevSecOps 기반 클라우드 보안 자동화 통합 서비스입니다. GitHub Actions, Terraform, AWS, Streamlit을 기반으로 코드 푸시부터 운영 중 위협 탐지까지, DevSecOps 파이프라인 전 과정을 자동화하는 것을 목표로 구축했습니다.

> 5인 팀 프로젝트(K-Digital Training)로 진행된 시스템이며, 이 레포에는 전체 코드가 포함되어 있습니다. 담당 역할은 하단 [담당 역할](#담당-역할) 섹션에 명시했습니다.

**진행 기간**: K-Digital Training 부트캠프 팀 프로젝트 (TEAM 5조)

---

## 배경 및 목표

클라우드 환경에서는 배포 전 자동 보안 검증이 필수입니다. 실제로 아래와 같은 사고들이 보안 자동화의 필요성을 보여줍니다.

- **Football Australia AWS 키 노출 사고 (2024)**: 웹사이트 소스코드에 AWS 자격증명이 하드코딩되어 S3 버킷 127개가 외부에 무단 노출
- **Uber AWS Credential 노출 사고 (2022)**: GitHub 코드 저장소에 AWS Access Key가 노출되어 공격자가 내부 AWS 환경에 접근

두 사고 모두 **하드코딩된 키, 개발 단계 보안 관리 미흡, Credential 관리 자동화 부족**이 원인이었습니다. 이 프로젝트는 이런 문제를 구조적으로 방지하기 위해 다음 목표로 설계했습니다.

- 배포 전 취약점 사전 차단
- 클라우드 보안 가시성 확보
- 보안 운영 효율성 향상
- DevSecOps 보안 프로세스 정착

---

## 프로젝트 개요

사용자는 서비스 코드만 업로드하고, 제공자(Provider)는 Dashboard를 통해 자동화된 DevSecOps 서비스를 제공하는 구조입니다.

```
User (main 브랜치)              Provider (web-service, Dashboard 실행)
 └ 서비스 코드 업로드      →      └ deploy.yml / terraform / k8s 업로드
                                   └ GitHub Actions 실행 및 결과 시각화
```

이 레포는 데모 서비스인 **ShopEasy**(쇼핑몰 예제 서비스)를 대상으로, 위 파이프라인 전체를 실제로 구축·검증한 결과물입니다.

---

## 시스템 아키텍처

### DevSecOps 자동화 파이프라인

```
Code Push → Semgrep Scan → Docker Build → Trivy Scan → Tfsec Scan
   → Terraform Apply → Deploy Service → Draw Infrastructure Map
   → Nuclei Scan → Prowler Scan → Falco Runtime Scan
   → Artifacts 저장 → Dashboard 시각화
```

<img src="pipeline-diagram.png" width="750">

각 보안 도구의 결과는 GitHub Actions artifacts로 저장되고, Web Dashboard에서 시각화되어 Scan 결과 페이지에서 확인할 수 있습니다.

### AWS 보안 기반 인프라 아키텍처

Public 노출 최소화, Private 중심 통신, 트래픽·워크로드·계정보호를 통합 설계했습니다.

<img src="architecture-diagram.png" width="900">

- **Edge Security**: CloudFront + WAF + Shield로 서비스 진입점 보호, X-Origin-Verify로 ALB 직접 접근 차단
- **Private Runtime Security**: EKS를 Private Subnet에 배치, Falco로 컨테이너 수준 이상행위 탐지
- **Security Data Pipeline**: 모든 보안 이벤트를 S3에 중앙 저장, Dashboard에서 실시간 분석
- **Multi-Account Governance**: Security Hub Findings 통합, Config 기반 규정 준수 관리

---

## 핵심 기술

### 1. DevSecOps 기반 CI/CD Pipeline 자동화

- **보안 내재화 자동 파이프라인**: 개발 단계부터 보안 점검(Semgrep, tfsec) 수행, 배포 전 취약점 검증 완료 구조(Trivy)
- **IaC 기반 인프라 재현성 확보**: Terraform으로 인프라 전체를 코드화해 동일 환경 자동 재구축 가능
- **Keyless 기반 안전 AWS 접근 구조**: OIDC 기반 Role Assume 방식으로 장기 Access Key를 사용하지 않음
- **배포 이후까지 이어지는 지속 보안 검증**: Runtime 탐지(Falco), 서비스 취약점 점검(Nuclei), 계정 보안 점검(Prowler)

> "Git Push부터 운영 점검까지 연결된 Lifecycle 보안 자동화 구현"

### 2. Public 노출 최소화 · Private 중심 통신 설계

- OIDC 기반 GitHub Actions ↔ AWS IAM Role 인증/권한 구조
- GuardDuty, CloudTrail, VPC Flow Logs, CloudWatch로 위협 탐지 및 모니터링
- Security Hub, Config, CloudFormation으로 보안 거버넌스 자동화

### 3. 전 단계 보안 검증을 위한 DevSecOps 도구 통합

| 단계 | 도구 | 점검 대상 | 확장 내용 |
|---|---|---|---|
| 코드 | Semgrep | 소스코드 정적 분석 | CWE 매핑 기반 취약점 분류, 조치 방법 및 참고 링크 제공 |
| IaC | tfsec | Terraform 보안 설정 점검 | 정책 위험도 분석 및 해결 가이드 번역본 자동 제공 |
| 이미지 | Trivy | Docker 이미지 CVE 진단 | 수정 가능 버전 명시 및 패키지 단위 상세 분석 결과 출력 |
| 서비스 | Nuclei | 배포된 실제 엔드포인트 | 실서비스 기준 점검으로 오탐 최소화 및 실제 공격 가능성 확인 |
| 인프라 | Prowler | AWS 계정 전체 보안 설정 | 기존 도구가 놓친 계정 수준 보안 항목 포함, CIS 벤치마크 기준 점검 |
| 런타임 | Falco | 실행 중 컨테이너 | 컨테이너 런타임 이상행위 실시간 탐지 및 보안 이벤트 로깅 |

> "코드부터 런타임까지 이어지는 다계층 보안 점검 자동화"

### 4. LLM 기반 취약점 분석 자동화

보안 점검 결과가 영어 원문 중심으로 출력되면 실사용 시 가독성 문제(CWE/CVE 이해 어려움, 즉시 조치 어려움)가 발생합니다. 이를 해결하기 위해 **단순 번역이 아닌 "조치 가능한 가이드"를 자동 생성**하는 구조를 구현했습니다.

- **1차: GitHub Actions 단계** — Google `deep-translator` 라이브러리로 스캔 결과를 한국어로 사전 번역 저장 (별도 API 키·비용 없이 `pip install`만으로 사용 가능, 매번 번역 API를 호출할 필요 없는 사전 캐싱 역할)
- **2차: Dashboard 단계** — Groq API(LLaMA 3.1 8B Instant)를 클라우드 보안 전문가 역할로 프롬프트 설계해 연동, 취약점 항목 클릭 시 **한국어 분석 리포트를 실시간 생성**
  - OWASP/CWE/CVE 기반 정확한 취약점 분석
  - 개발자가 즉시 적용 가능한 단계별 조치 방법 제공
  - 심각도(Critical/High/Medium/Low)에 따른 우선순위 판단
- LPU 전용 하드웨어 기반이라 GPT-4o, Claude 대비 응답 속도가 빠른 점을 고려해 Groq API 채택

---

## 대시보드 주요 기능

| 기능 | 설명 |
|---|---|
| **Keyless Deployment** | CloudFormation 스택 실행 시 IAM Role + OIDC Provider 자동 생성 → Role ARN을 PyNaCl로 암호화해 GitHub Secrets에 저장 → 워크플로우 실행 시 OIDC 토큰으로 AWS 임시 자격증명 획득 |
| **Pipeline Visibility** | GitHub Actions REST API 연동, 30초 주기로 자동 폴링해 각 Job 상태(성공/실패/진행/건너뜀)를 색상 인디케이터로 표현 |
| **Infra Mapping** | boto3(AWS SDK) 기반으로 EC2/EKS/RDS/ALB/WAF/VPC 정보를 자동 수집, Multi-AZ 및 Public/Private Subnet 구조를 시각화 |
| **Security Insight** | 6개 보안 도구 결과를 GitHub Actions Artifact에서 수집, JSON 파싱 후 WARNING/RISK/SAFE 등급으로 자동 분류, 배포 완료 후 CloudFront URL 자동 추출 |
| **AI Response Guide** | 취약점 클릭 시 LLM이 파일/라인/RuleID 기반 상세 조치 가이드를 실시간 생성 |

**Security Insight 화면**

<img src="dashboard-security-insight.png" width="500">

**AI 기반 조치 가이드 화면**

<img src="dashboard-ai-guide.png" width="500">

---

## 한계점 및 개선방향

- **CloudFormation 템플릿 내 Git 정보 하드코딩**: 고객별 동적 변수 주입이 불가한 구조 → CloudFormation Parameter를 활용해 웹 UI에서 레포명을 입력받아 동적 주입하도록 개선 가능
- **취약점 탐지 시 파이프라인 차단 기능 미구현**: 전체 취약점 제거가 현실적으로 불가해 배포 차단 로직은 미적용 → 추가 시 완전한 DevSecOps 파이프라인 구축 가능
- **ShopEasy 종속적 IaC 구조**: Terraform/k8s 코드가 데모 서비스(ShopEasy) 구조를 전제로 작성되어 타 서비스 레포 업로드 시 배포 실패 가능 → 고객 레포 구조 분석 후 동적 생성 로직 필요
- **Nuclei/Falco 점검 결과 0건**: 배포 및 접속 확인 수준에서 시연이 종료되어 실제 웹 사용이 없어 런타임 위협이 탐지되지 않음 → 의도적 취약 서비스 배포 또는 실 트래픽 발생 시나리오 추가 필요

---

## Prerequisite: role.yml 설정

`role.yml`(IAM Role 생성용 CloudFormation 템플릿)은 사용자 AWS 계정이 아닌 **플랫폼 제공자(관리자) 계정**에서 미리 생성해야 합니다.

```
Provider AWS Account          User AWS Account
 └ S3 Bucket                   └ CloudFormation
     └ role.yml                    └ role.yml 실행 → IAM Role 생성
```

이 프로젝트는 사용자의 AWS 계정에 직접 접근하지 않고, **CloudFormation + IAM Role 위임 방식**으로 권한을 획득합니다. 절차:

1. 제공자 AWS 계정에서 IAM Role 생성용 CloudFormation 템플릿(`role.yml`) 준비
2. `role.yml`을 S3 버킷에 업로드
3. S3 공개 URL을 Dashboard에서 사용

---

## 사용 기술

| Tech | Usage |
|---|---|
| Python | Backend |
| Streamlit | Dashboard |
| GitHub Actions | CI/CD |
| Terraform | IaC |
| AWS | Cloud |
| Docker | Container |
| Semgrep | Code Scan |
| Trivy | Image Scan |
| Tfsec | IaC Scan |
| Nuclei | Endpoint Scan |
| Prowler | AWS Scan |
| Falco | Runtime Scan |
| Groq API (LLaMA 3.1 8B) | LLM 기반 조치 가이드 생성 |
| deep-translator | 스캔 결과 사전 번역 |

---

## 디렉토리 구조

```
aws-security-service-project/
├── README.md
├── .github/
│   └── workflows/
│       ├── deploy.yml      # DevSecOps 전과정 자동화 파이프라인
│       └── falco.yml       # 컨테이너 런타임 취약점 분석 (주기적 실행)
├── frontend/                # ShopEasy 프론트엔드 (React + Vite)
├── api-server/               # ShopEasy API 서버 (Node.js)
├── k8s/                       # Kubernetes 매니페스트 (deployment, service, ingress)
└── shopeasy-terraform/         # AWS 인프라 IaC (EKS, RDS, VPC, WAF, GuardDuty 등)
```

---

## 담당 역할

5인 팀 프로젝트 중 다음 부분을 담당했습니다.

- **인프라 구축**: Terraform 기반 AWS 인프라 구축
- **CI/CD 및 배포 자동화**: GitHub Actions 기반 배포 자동화 파이프라인 구현
- **테스트**: 단위/통합 테스트
- **프로젝트 관리**: 프로젝트 관리 체계 수립, 보고서 작성 및 발표

---

## Notes

- Token은 서버에 저장되지 않으며, ARN 기반 권한 위임 방식을 사용합니다
- AWS 직접 로그인 없이 GitHub REST API를 통해서만 동작합니다
- Scan 결과는 GitHub Actions artifacts로 저장됩니다
