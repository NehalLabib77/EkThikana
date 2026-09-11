import os
import json
import base64

import firebase_admin
from firebase_admin import credentials, auth

b64 = os.environ.get("FIREBASE_SERVICE_ACCOUNT_B64")
test_email = os.environ.get("TEST_USER_EMAIL")

if not b64:
    raise SystemExit("FIREBASE_SERVICE_ACCOUNT_B64 is not set")

if not test_email:
    raise SystemExit("TEST_USER_EMAIL is not set")

service_account_info = json.loads(
    base64.b64decode(b64).decode("utf-8")
)

cred = credentials.Certificate(service_account_info)
firebase_admin.initialize_app(cred)

user = auth.get_user_by_email(test_email)

updated = auth.update_user(
    user.uid,
    email_verified=True,
)

print("Email:", updated.email)
print("UID:", updated.uid)
print("Email verified:", updated.email_verified)