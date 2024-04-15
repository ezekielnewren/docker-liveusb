import sys

import ykman.scripting
from yubikit.piv import PivSession, MANAGEMENT_KEY_TYPE, DEFAULT_MANAGEMENT_KEY, SLOT

from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.backends import default_backend
import binascii

t = ykman.scripting.single()
sc = t.smart_card()
piv = PivSession(sc)
piv.authenticate(MANAGEMENT_KEY_TYPE.TDES, DEFAULT_MANAGEMENT_KEY)
piv.verify_pin("123456")

slot = SLOT.KEY_MANAGEMENT
meta = piv.get_slot_metadata(slot)
pk = meta.public_key

salt = sys.argv[1].encode("utf-8")
ikm = piv.calculate_secret(slot, pk)

hkdf = HKDF(
    algorithm=hashes.SHA256(),
    length=32,  # Desired length of the derived key in bytes
    salt=salt,  # Optionally, a non-secret random value
    info=b'',  # Optional context and application specific information
    backend=default_backend()
)

unlock_key = hkdf.derive(ikm)
print(unlock_key.hex())

sc.close()

