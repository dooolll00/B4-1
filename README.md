# Codyssey B4-1

Ubuntu 서버에 SSH·방화벽·협업 권한을 구성하고, 제공 앱의 상태와 시스템 자원을 Bash로 수집해 매분 기록한 수행 내역서입니다. 제출 소스는 [monitor.sh](monitor.sh)입니다.

## 검증 범위

- 실제 서버: 사용자 제공 터미널 기록과 캡처에서 Ubuntu 24.04 LTS, x86-64, Bash, UFW, cron 사용을 확인했습니다. Ubuntu 22.04 LTS와 동등 리눅스 환경 조건에 해당합니다.
- 실제 실행: 일반 계정의 앱 부팅, 프로세스·포트 점검, 자원 수집, 경고, 로그 누적, cron 실행을 확인했습니다.
- 실제 로테이션 시험: 서버의 스크립트를 복사해 로그 경로만 임시 디렉터리로 바꿔 실행했습니다. 실행 중 앱과 운영 로그는 유지했습니다.
- 2026-11-08 로컬 보강: 로그 쓰기·회전 실패 시 종료 처리를 추가했습니다. 명령 대역 검사 후 서버 반영·실제 실행 및 임시 로그 회전·쓰기 실패 검증도 완료했습니다. 기존 서버 캡처는 보강 전 버전이며 최신 결과는 [서버 반영 검증](docs/server-deployment.md)에 기록했습니다.

## 1. SSH와 방화벽

SSH는 20022로 변경하고 Root 원격 로그인을 차단했습니다. Ubuntu의 SSH socket 설정도 조정해 최종 IPv4 리스닝 결과에서 20022만 확인했습니다. 포트 변경은 불필요한 기본 포트 접근을 줄이고, Root 로그인 차단은 일반 계정과 필요한 sudo 권한을 사용하게 합니다.

실제 설정 파일은 `/etc/ssh/sshd_config.d/00-mission-security.conf`이며 검증 명령은 다음과 같습니다.

```bash
sudo sshd -t
sudo sshd -T | grep -E '^(port|permitrootlogin) '
sudo ss -4 -ltnp | grep -E ':(22|20022)\b'
```

결과: `port 20022`, `permitrootlogin no`, IPv4 20022 리스닝. 설정 과정에서 잠시 존재했던 22 리스닝은 최종 기록에서 제거됐습니다.

<a href="docs/screenshots/05-ssh-security.png"><img src="docs/screenshots/05-ssh-security.png" alt="SSH 유효 설정" width="800"></a>

UFW는 활성화했고 기본 인바운드는 deny, 아웃바운드는 allow로 설정되어 있습니다. 전환 중 허용했던 22/tcp 규칙은 삭제했고, 최종 TCP 허용 포트는 20022와 15034입니다. IPv6에도 같은 두 포트의 규칙이 있습니다.

```bash
sudo ufw allow 20022/tcp
sudo ufw allow 15034/tcp
sudo ufw enable
sudo ufw delete allow 22/tcp
sudo ufw status verbose
```

위 명령은 수행 기록을 정리한 것이며 서버에서 재실행할 필요는 없습니다. 기본 deny 정책은 첨부 터미널 기록의 `Default: deny (incoming)`으로 확인했습니다.

<a href="docs/screenshots/06-ufw-rules.png"><img src="docs/screenshots/06-ufw-rules.png" alt="UFW 활성 상태 및 규칙" width="800"></a>

AWS 보안 그룹도 지정 IP에서 두 포트만 허용한 화면을 확보했습니다. 보안 그룹은 호스트 UFW와 별개의 제어입니다.

<a href="docs/screenshots/11-aws-security-group.png"><img src="docs/screenshots/11-aws-security-group.png" alt="AWS 인바운드 규칙" width="800"></a>

## 2. 계정·그룹·디렉터리 권한

| 대상 | 구성 |
|---|---|
| agent-admin | agent-common, agent-core / 앱·cron 실행 |
| agent-dev | agent-common, agent-core / 스크립트 작성 |
| agent-test | agent-common / QA |
| 앱 홈 | agent-admin:agent-common, 2750 (최終 보강) |
| upload_files | agent-admin:agent-common, 2770 |
| api_keys, /var/log/agent-app | agent-admin:agent-core, 2770 |
| bin | agent-dev:agent-core, 2770 |
| bin/monitor.sh | agent-dev:agent-core, 실효 권한 750 |

앱 홈 자체는 common 그룹의 읽기·통과만 허용해 agent-test가 보안 디렉터리를 이름 변경·교체할 수 없도록 했습니다. upload_files 공유 디렉터리는 common 그룹이 읽고 쓸 수 있고, 키와 로그 디렉터리는 core 그룹으로 제한합니다. 디렉터리의 setgid는 새 파일의 그룹 상속을, 기본 ACL은 하위 파일의 권한 상속을 지원합니다. agent-admin 홈에는 common 그룹의 경로 통과 권한을 부여했습니다.

실제 설정·확인에 사용한 명령 형태입니다. `<대상>`은 해당 디렉터리로 바꾸는 자리표시자입니다.

```bash
sudo groupadd agent-common
sudo groupadd agent-core
sudo useradd -m -s /bin/bash agent-admin
sudo useradd -m -s /bin/bash agent-dev
sudo useradd -m -s /bin/bash agent-test
sudo usermod -aG agent-common,agent-core agent-admin
sudo usermod -aG agent-common,agent-core agent-dev
sudo usermod -aG agent-common agent-test
id agent-admin
id agent-dev
id agent-test
sudo chmod 2770 <대상>
sudo setfacl -d -m g::rwx,m::rwx,o::--- <대상>
sudo chmod 2750 /home/agent-admin/agent-app
sudo setfacl -m g:agent-common:--x /home/agent-admin
sudo getfacl <대상>
sudo chown agent-dev:agent-core /home/agent-admin/agent-app/bin/monitor.sh
sudo chmod 750 /home/agent-admin/agent-app/bin/monitor.sh
```

<a href="docs/screenshots/07-users-groups.png"><img src="docs/screenshots/07-users-groups.png" alt="사용자 및 그룹" width="800"></a>

<a href="docs/screenshots/08-directory-acl.png"><img src="docs/screenshots/08-directory-acl.png" alt="디렉터리 ACL" width="800"></a>

초기 앱 홈은 2770이었으나 최종 재검토에서 2750으로 보강했습니다. 하위 공유·보안 디렉터리 권한은 유지했고 세 계정의 업로드 쓰기, agent-test의 키·로그 접근 차단, agent-dev의 스크립트 쓰기를 서버에서 재확인했습니다. 최신 상태는 [최종 검토](docs/final-review.md)에 정리했습니다.

<a href="docs/screenshots/09-monitor-permissions.png"><img src="docs/screenshots/09-monitor-permissions.png" alt="서버 스크립트 소유자 및 권한" width="800"></a>

추가로 제공한 상세 ACL 화면에서 스크립트의 `user::rwx`, `group::rwx`, `mask::r-x`, `other::---`를 확인했습니다. 그룹의 실효 권한은 r-x로, 전체 실효 권한은 750입니다. 해당 화면을 아래 증빙으로 저장했습니다.

<a href="docs/screenshots/14-monitor-acl.png"><img src="docs/screenshots/14-monitor-acl.png" alt="monitor.sh 상세 ACL" width="800"></a>

실제 접근 시험에서는 agent-test의 api_keys·로그 디렉터리 접근이 거부됐고, agent-dev·admin의 로그 쓰기는 성공했습니다. 저장소의 실행 비트와 서버의 750 소유권 설정은 구분합니다.

## 3. 제공 앱 실행과 키 경로 호환 처리

실행 환경은 agent-admin의 `.agent-env`에 두고 로그인 시 `.profile`에서 읽도록 구성했습니다. 환경변수의 실제 값과 키 내용은 이 문서에 복사하지 않습니다.

| 환경변수 | 용도 |
|---|---|
| AGENT_HOME | 앱 홈 기준 경로 |
| AGENT_PORT | 앱 포트 지정 |
| AGENT_UPLOAD_DIR | 공유 업로드 디렉터리 지정 |
| AGENT_KEY_PATH | 제공 앱의 키 검색 위치 지정 |
| AGENT_LOG_DIR | 로그 디렉터리 지정 |

미션은 AGENT_KEY_PATH에 `t_secret.key` 파일 경로를 요구하지만, 제공된 x86 실행파일은 api_keys **디렉터리**를 요구했습니다. 파일 경로로 실행하면 `Key Path Mismatch`가 나왔고, 디렉터리로 바꾸면 `secret.key`를 찾는다는 오류가 나왔습니다.

미션의 `t_secret.key`를 보존한 채 동일 내용의 `secret.key`를 준비하고, 앱이 요구하는 디렉터리 경로를 지정해 실행했습니다. 이는 제공 앱과 미션 문구 사이의 차이에 대한 호환 조치이며, 원문과 완전히 같은 설정이라고 주장하지 않습니다. 키 파일 내용은 저장소에 포함하지 않습니다.

```bash
sudo cp /home/agent-admin/agent-app/api_keys/t_secret.key /home/agent-admin/agent-app/api_keys/secret.key
sudo chown agent-admin:agent-core /home/agent-admin/agent-app/api_keys/secret.key
sudo chmod 660 /home/agent-admin/agent-app/api_keys/secret.key
sudo cmp -s /home/agent-admin/agent-app/api_keys/secret.key /home/agent-admin/agent-app/api_keys/t_secret.key && echo '동일 내용 확인'
sudo -u agent-admin -H bash -l -c 'cd "$AGENT_HOME" && ./agent-app-linux-x86'
```

일반 계정 agent-admin으로 5단계 [OK]와 Agent READY를 확인했습니다. 실제 `ss` 결과에서도 IPv4 전체 인터페이스의 앱 포트 리스닝을 확인했습니다.

<a href="docs/screenshots/04-app-boot.png"><img src="docs/screenshots/04-app-boot.png" alt="앱 Boot Sequence 및 Agent READY" width="800"></a>

후속 로그인 설정에서 키 경로가 다시 파일로 지정된 것을 확인해, 2026-11-08 제공 앱이 요구하는 디렉터리로 다시 맞췄습니다. 실행 중인 앱을 종료하지 않고 다음 로그인·실행 설정을 수정했습니다.

<a href="docs/screenshots/12-key-path-fix.png"><img src="docs/screenshots/12-key-path-fix.png" alt="키 경로 수정 전후" width="800"></a>

## 4. monitor.sh 구현 및 실행

- agent-admin 소유의 앱 프로세스와 TCP 15034 LISTEN을 확인하며 실패 시 exit 1입니다.
- `sudo -n ufw status`로 방화벽을 확인합니다. 비활성 또는 조회 불가는 WARNING 후 계속합니다.
- 자원 수집은 C 로케일에서 실행하며 명령 실패·누락·잘못된 수치는 ERROR와 exit 1로 처리해 정상 측정값처럼 기록하지 않습니다.
- CPU는 top의 idle 비율을 제외한 값, 메모리는 `(total - available) / total`, 디스크는 루트 파티션 Used %입니다.
- CPU > 20%, MEM > 10%, DISK > 80%이면 WARNING을 출력합니다.
- 로그 형식은 `[YYYY-MM-DD HH:MM:SS] PID:... CPU:...% MEM:...% DISK_USED:...%`입니다.
- 새 줄을 추가했을 때 10MiB(10 × 1024 × 1024바이트)를 넘으면 먼저 회전합니다. 현재 로그와 `.1`~`.9`를 합쳐 최대 10개를 유지합니다. 외부에서 이미 10MiB를 초과하도록 만든 파일을 줄이는 기능은 없습니다.
- 로컬 보강본은 크기 조회, 오래된 로그 삭제, 파일 이동, 로그 추가 실패 시 ERROR와 exit 1을 반환합니다. 실패한 경우 성공 메시지를 출력하지 않습니다. 회전 도중 실패하면 일부 파일 이동은 이미 수행됐을 수 있습니다.

실제 첫 실행에서는 UFW가 활성인데도 agent-admin의 비밀번호 없는 조회 권한이 없어 WARNING이 나왔습니다. sudoers 설정 후 구문 검사와 비대화식 조회 성공을 확인했고, 이후 WARNING 없이 정상 점검됐습니다. sudoers 파일 내용 자체는 첨부 기록에 출력되지 않았습니다.

```bash
sudo visudo -cf /etc/sudoers.d/agent-ufw-status
sudo -u agent-admin -H sudo -n /usr/sbin/ufw status
sudo -u agent-admin -H /home/agent-admin/agent-app/bin/monitor.sh
```

<a href="docs/screenshots/03-monitor-output.png"><img src="docs/screenshots/03-monitor-output.png" alt="실제 monitor 실행 및 경고" width="800"></a>

## 5. cron 및 로그 누적

agent-admin의 crontab에 등록한 실제 실행 줄입니다.

```cron
* * * * * /home/agent-admin/agent-app/bin/monitor.sh >> /var/log/agent-app/cron.log 2>&1
```

```bash
sudo crontab -u agent-admin -l
sudo -u agent-admin tail -n 5 /var/log/agent-app/monitor.log
sudo -u agent-admin tail -n 15 /var/log/agent-app/cron.log
```

13:33~13:37 등 연속된 분의 새 로그와 cron 출력에서 자동 실행을 확인했습니다. 표기 시각은 서버 UTC이며 한국 시간과 9시간 차이가 있습니다. cron.log는 콘솔 출력 확인용이고 monitor.log의 회전 대상에는 포함되지 않습니다.

<a href="docs/screenshots/01-cron-schedule.png"><img src="docs/screenshots/01-cron-schedule.png" alt="agent-admin 매분 cron 등록" width="800"></a>

<a href="docs/screenshots/02-cron-log-accumulation.png"><img src="docs/screenshots/02-cron-log-accumulation.png" alt="분 단위 로그 누적 및 cron 출력" width="800"></a>

## 6. 로테이션 검증

초기 11MiB 파일 시험은 회전 부분만 분리한 시험입니다. 그 뒤 실제 서버 monitor.sh의 로그 경로 한 줄만 `/tmp`의 새 임시 폴더로 변경해 전체 복사본을 실행했습니다.

- 실행 전: 현재 로그 10,485,760바이트, 기존 회전 파일 9개.
- 실행 후: 현재 로그 65바이트, `.1`은 10,485,760바이트, 총 파일 10개.
- 가장 오래된 마커 제거·순번 이동·새 로그 생성·파일당 최대 크기를 검사해 PASS를 확인했습니다.
- 앞선 작업 디렉터리 권한 경고는 `cd /tmp`를 추가한 재실행에서 해소됐습니다.

<a href="docs/screenshots/13-rotation-before.png"><img src="docs/screenshots/13-rotation-before.png" alt="전체 복사본 시험의 경로 차이와 실행 전 크기" width="800"></a>

실행 후 크기·총 10개·PASS를 아래 실제 서버 시험 화면에서 확인할 수 있습니다.

<a href="docs/screenshots/15-rotation-after.png"><img src="docs/screenshots/15-rotation-after.png" alt="전체 복사본 시험의 회전 결과 및 PASS" width="800"></a>

아래 초기 이미지는 별도 회전 로직 시험이며 위 전체 실행과 구분합니다.

<a href="docs/screenshots/10-rotation-test.png"><img src="docs/screenshots/10-rotation-test.png" alt="초기 분리 로직 시험" width="800"></a>

## 7. 로컬 보강본 회귀 검사

```bash
bash -n monitor.sh
python3.12 -m unittest discover -s tests -v
```

6개 테스트 메서드가 통과했습니다. 프로세스·포트 실패, 방화벽·자원 경고 후 지속, 자원 수집 명령 실패·잘못된 출력, 로그 포맷, 10MiB 경계 회전 및 파일 수, 로그 추가 실패와 stat/rm/mv 실패 시 비정상 종료를 검사합니다. 분기별 사례는 subTest로 확인합니다.

이 검사는 Python 표준 라이브러리로 Bash를 호출하고 명령 대역을 주입합니다. 관제 구현 자체는 Bash이며 실제 Ubuntu 명령·방화벽·cron 동작을 로컬에서 재검증한 결과는 아닙니다. 운영 로그는 건드리지 않고 임시 파일만 사용합니다.

## 제출 상태 및 남은 작업

- 실제 서버 캡처 및 사용자 제공 기록은 오류 처리·앱 홈 권한 보강 전 실행의 증빙입니다. 최신 직접 검사 결과는 [최종 검토](docs/final-review.md)에 기록했습니다.
- 오류 처리 보강본의 서버 배포·정상 실행·임시 환경 회전 및 쓰기 실패·다음 분 cron 로그 추가를 확인했습니다. 최신 로컬/서버 SHA-256 일치는 [서버 반영 검증](docs/server-deployment.md)에 기록했습니다.
- 상세 ACL·최종 로테이션 결과 이미지까지 저장하고 본문에 연결했습니다.
- 보너스 report.sh와 7일 압축·30일 삭제 정책은 구현하지 않았습니다.
- 최신 monitor.sh와 앱 홈 권한은 서버에 반영했습니다. 최신 코드·문서·증빙의 GitHub 업로드는 미수행입니다.

키·비밀번호·SSH 개인키·원본 환경설정·원본 운영 로그는 저장소에 포함하지 않습니다. 캡처는 제출 증빙으로만 보관합니다.
