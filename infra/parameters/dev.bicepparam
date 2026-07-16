using '../main.bicep'

// suffix는 지정하지 않으면 배포 시점 날짜로 자동 생성됩니다 (aigateway-YYYYMMDD).
// deploy.sh는 오늘 날짜(로컬)를 사용하고, 직접 bicep 배포 시엔 main.bicep의 utcNow 기본값이 적용됩니다.
// 고정 값을 쓰려면 아래 주석을 해제하고 원하는 suffix로 변경하세요.
// param suffix = 'aigateway-20260716'
param apimSku = 'Developer'
param publisherEmail = 'changjuahn@microsoft.com'
param publisherName = 'AI Gateway Lab'
