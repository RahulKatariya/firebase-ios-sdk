/*
 * Copyright 2018 Google
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#ifndef FIRESTORE_CORE_SRC_FIREBASE_FIRESTORE_MODEL_DOCUMENT_H_
#define FIRESTORE_CORE_SRC_FIREBASE_FIRESTORE_MODEL_DOCUMENT_H_

#include <iosfwd>
#include <string>

#if __OBJC__
#import "Firestore/Source/Model/FSTDocument.h"
#endif

#include "Firestore/core/src/firebase/firestore/model/field_path.h"
#include "Firestore/core/src/firebase/firestore/model/field_value.h"
#include "Firestore/core/src/firebase/firestore/model/maybe_document.h"
#include "absl/types/optional.h"

namespace firebase {
namespace firestore {
namespace model {

/** Describes the `hasPendingWrites` state of a document. */
enum class DocumentState {
  /**
   * Local mutations applied via the mutation queue. Document is potentially
   * inconsistent.
   */
  kLocalMutations,

  /**
   * Mutations applied based on a write acknowledgment. Document is potentially
   * inconsistent.
   */
  kCommittedMutations,

  /** No mutations applied. Document was sent to us by Watch. */
  kSynced,
};

std::ostream& operator<<(std::ostream& os, DocumentState state);

/**
 * Represents a document in Firestore with a key, version, data and whether the
 * data has local mutations applied to it.
 */
class Document : public MaybeDocument {
 public:
  /**
   * Construct a document. ObjectValue must be passed by rvalue.
   */
  Document(ObjectValue&& data,
           DocumentKey key,
           SnapshotVersion version,
           DocumentState document_state);

#if __OBJC__
  explicit Document(FSTDocument* doc)
      : MaybeDocument(doc.key, doc.version),
        data_(doc.data),
        document_state_(doc.documentState) {
  }

  FSTDocument* ToDocument() const {
    return [FSTDocument documentWithData:data_
                                     key:key()
                                 version:version()
                                   state:document_state_];
  }
#endif  // __OBJC__

  const ObjectValue& data() const {
    return data_;
  }

  absl::optional<FieldValue> field(const FieldPath& path) const {
    return data_.Get(path);
  }

  bool HasLocalMutations() const {
    return document_state_ == DocumentState::kLocalMutations;
  }

  bool HasCommittedMutations() const {
    return document_state_ == DocumentState::kCommittedMutations;
  }

  bool HasPendingWrites() const override {
    return HasLocalMutations() || HasCommittedMutations();
  }

  std::string ToString() const;

  friend std::ostream& operator<<(std::ostream& os, const Document& doc);

 protected:
  bool Equals(const MaybeDocument& other) const override;

 private:
  ObjectValue data_;
  DocumentState document_state_;
};

/** Compares against another Document. */
inline bool operator==(const Document& lhs, const Document& rhs) {
  return lhs.version() == rhs.version() && lhs.key() == rhs.key() &&
         lhs.HasLocalMutations() == rhs.HasLocalMutations() &&
         lhs.data() == rhs.data();
}

inline bool operator!=(const Document& lhs, const Document& rhs) {
  return !(lhs == rhs);
}

}  // namespace model
}  // namespace firestore
}  // namespace firebase

#endif  // FIRESTORE_CORE_SRC_FIREBASE_FIRESTORE_MODEL_DOCUMENT_H_
