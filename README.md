# Codyssey B4-1
## Ubuntu Linux Security and System Monitoring

### 1. 프로젝트 개요
Ubuntu Linux 환경에서 서버 보안 설정과 애플리케이션 실행 환경을 구성하고, Bash 스크립트를 이용한 시스템 모니터링 및 자동 로그 관리를 구현한다.

### 2. 개발 환경
- OS: Ubuntu Linux
- Shell: Bash
- Version Control: Git / GitHub
- Scheduler: cron

### 3. 주요 구현 내용

#### SSH 보안
- SSH 접속 포트 20022 설정
- Root 원격 로그인 차단

#### 방화벽
- UFW 활성화
- TCP 20022(SSH), 15034(APP) 허용

#### 계정 및 그룹
- 사용자: agent-admin, agent-dev, agent-test
- 그룹: agent-common, agent-core
- 역할 기반 계정 및 그룹 구성

#### 디렉터리 및 권한
- upload_files: agent-common 그룹 공유
- api_keys: agent-core 그룹 접근
- /var/log/agent-app: agent-core 그룹 접근
- ACL을 통한 기본 접근 권한 설정

#### 애플리케이션 실행 환경
- AGENT_HOME
- AGENT_PORT
- AGENT_UPLOAD_DIR
- AGENT_KEY_PATH
- AGENT_LOG_DIR

#### 시스템 모니터링 (monitor.sh)
- 애플리케이션 프로세스 상태 확인
- TCP 15034 포트 LISTEN 확인
- 방화벽 활성화 상태 점검
- CPU, 메모리, 디스크 사용률 수집
- 임계값 초과 시 WARNING 출력
- 모니터링 결과 로그 기록

#### 로그 관리
- 로그 위치: /var/log/agent-app/monitor.log
- 파일 크기 기준: 10MB
- 최대 보관 파일 수: 10개
- Bash 스크립트 기반 로그 로테이션 구현

#### 자동 실행 (cron)
- 실행 계정: agent-admin
- 실행 주기: 매분
- monitor.sh 자동 실행 및 로그 누적 확인

### 4. 테스트 및 검증
- 프로세스 및 포트 상태 확인
- CPU, 메모리, 디스크 사용률 출력 확인
- 임계값 경고 출력 확인
- 로그 기록 및 자동 실행 확인
- 11MB 테스트 파일을 이용한 로그 로테이션 검증
- 스크립트 권한 및 소유자 확인

### 5. 주요 파일
- monitor.sh: 시스템 상태 수집 및 로그 관리 Bash 스크립트
- .gitignore: 민감정보 및 로그 파일 업로드 방지

### 6. 참고 사항
제공된 애플리케이션의 AGENT_KEY_PATH 요구 경로와 미션 문서의 지정 경로 사이에 불일치가 확인되어 추가 확인이 필요하다.

### 7. 보안
API 키, SSH 개인키, 서버 인증서 및 실제 운영 로그는 저장소에 업로드하지 않는다.
