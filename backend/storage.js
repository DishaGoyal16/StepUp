const crypto = require("crypto");
const fs = require("fs/promises");
const path = require("path");
const os = require("os");
const { createWriteStream } = require("fs");
const { pipeline } = require("stream/promises");
const { S3Client, PutObjectCommand, GetObjectCommand, DeleteObjectCommand } = require("@aws-sdk/client-s3");

const bucket = process.env.S3_BUCKET;
const s3 = bucket ? new S3Client({ region: process.env.AWS_REGION }) : null;

function validStorageKey(key) {
  return typeof key === "string" && /^[a-zA-Z0-9][a-zA-Z0-9.-]*$/.test(key);
}

async function readFromS3(key) {
  let object;
  try {
    object = await s3.send(new GetObjectCommand({ Bucket: bucket, Key: key }));
  } catch (error) {
    if (error.name === "NoSuchKey" || error.$metadata?.httpStatusCode === 404) return null;
    throw error;
  }

  const directory = await fs.mkdtemp(path.join(os.tmpdir(), "stepup-download-"));
  const filePath = path.join(directory, key);
  const cleanup = () => fs.rm(directory, { recursive: true, force: true });
  try {
    await pipeline(object.Body, createWriteStream(filePath, { flags: "wx", mode: 0o600 }));
    return { path: filePath, cleanup };
  } catch (error) {
    await cleanup();
    throw error;
  }
}

const localUploadDirectory = path.resolve(
  process.env.UPLOAD_STORAGE_PATH || path.join(__dirname, "uploads")
);

function safeExtension(filename) {
  const extension = path.extname(filename || "").toLowerCase();
  return /^[.a-z0-9]{0,12}$/.test(extension) ? extension : "";
}

const storage = {
  async save({ buffer, originalFilename }) {
    const storageKey = `${crypto.randomUUID()}${safeExtension(originalFilename)}`;
    if (s3) {
      await s3.send(new PutObjectCommand({
        Bucket: bucket,
        Key: storageKey,
        Body: buffer,
        IfNoneMatch: "*",
      }));
    } else {
      await fs.mkdir(localUploadDirectory, { recursive: true, mode: 0o700 });
      await fs.writeFile(path.join(localUploadDirectory, storageKey), buffer, { flag: "wx", mode: 0o600 });
    }
    return { storageKey, storageUrl: null };
  },

  async read(storageKey) {
    if (!validStorageKey(storageKey)) return null;
    if (s3) return readFromS3(storageKey);
    const filePath = path.join(localUploadDirectory, storageKey);
    try {
      await fs.access(filePath);
      return { path: filePath };
    } catch {
      return null;
    }
  },

  async remove(storageKey) {
    if (!validStorageKey(storageKey)) return;
    if (s3) {
      await s3.send(new DeleteObjectCommand({ Bucket: bucket, Key: storageKey }));
      return;
    }
    await fs.rm(path.join(localUploadDirectory, storageKey), { force: true });
  },
};

module.exports = storage;
